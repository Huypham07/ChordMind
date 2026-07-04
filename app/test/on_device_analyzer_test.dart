// Task B1.5: OnDeviceAnalyzer assembles the AnalysisResult JSON from the
// B1.1-B1.4 pieces (AudioSource -> PcmInferenceRunner -> voteDecode ->
// estimateKey) plus a synthetic placeholder-BPM beat grid, and
// DefaultSongRepository.generate wires it in.
//
// No network: AudioSource is faked with the real multi-window PCM fixture
// already used by pcm_runner_test.dart (test/fixtures/pcm_runner_pcm.bin),
// so this test exercises real ORT inference against the bundled
// chordnet_2e1d.onnx (synced via tool/sync_models.sh) end-to-end.
import 'dart:io';
import 'dart:typed_data';

import 'package:chordmind/core/api.dart';
import 'package:chordmind/core/audio_source.dart';
import 'package:chordmind/core/local_store.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/on_device_analyzer.dart';
import 'package:chordmind/core/song_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fixturesDir = 'test/fixtures';

Float32List _readF32(String path) {
  final bytes = File(path).readAsBytesSync();
  return bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 4);
}

/// Fake AudioSource: returns a fixed, real-audio PCM fixture instead of
/// hitting the network, so tests are hermetic and fast.
class _FixturePcmAudioSource extends AudioSource {
  _FixturePcmAudioSource(this._pcm);
  final Float32List _pcm;

  @override
  Future<Float32List> pcm(String youtubeId) async => _pcm;
}

final _keyPattern = RegExp(r'^[A-G](#|b)? (major|minor)$');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    OrtEnv.instance.init();
  });

  tearDownAll(() {
    OrtEnv.instance.release();
  });

  late Float32List fixturePcm;
  setUpAll(() {
    fixturePcm = _readF32('$_fixturesDir/pcm_runner_pcm.bin');
  });

  group('OnDeviceAnalyzer', () {
    test('assembles a valid AnalysisResult JSON from fixture PCM', () async {
      final analyzer = OnDeviceAnalyzer(audioSource: _FixturePcmAudioSource(fixturePcm));

      final json = await analyzer.analyze('testid', title: 'T');

      // Round-trips through AnalysisResult.fromJson without throwing.
      final result = AnalysisResult.fromJson(json);

      expect(result.songId, 'testid');
      expect(result.source.title, 'T');
      expect(result.source.duration, closeTo(fixturePcm.length / 22050, 1e-6));

      expect(result.chords, isNotEmpty);

      expect(result.beats, isNotEmpty);
      for (var i = 1; i < result.beats.length; i++) {
        final dt = result.beats[i].time - result.beats[i - 1].time;
        expect(dt, closeTo(0.5, 1e-6)); // 60/120 bpm
      }
      // beatNum cycles 1..4.
      for (var i = 0; i < result.beats.length; i++) {
        expect(result.beats[i].beatNum, i % 4 + 1);
      }
      // downbeats are exactly the beatNum==1 times.
      final expectedDownbeats = [
        for (final b in result.beats)
          if (b.beatNum == 1) b.time,
      ];
      expect(result.downbeats, expectedDownbeats);

      expect(result.synchronizedChords, hasLength(result.beats.length));
      for (final sc in result.synchronizedChords) {
        expect(sc.beatIndex, greaterThanOrEqualTo(0));
        expect(sc.beatIndex, lessThan(result.beats.length));
      }

      expect(result.key, matches(_keyPattern));

      expect(result.segments, isEmpty);
    });

    test('honors an explicit modelName (btc) instead of the registry default', () async {
      final analyzer = OnDeviceAnalyzer(audioSource: _FixturePcmAudioSource(fixturePcm));

      final json = await analyzer.analyze('testid', title: 'T', modelName: 'btc');
      final result = AnalysisResult.fromJson(json);

      // btc has the same fs/windowSamples as chordnet_2e1d (see manifest),
      // so the pipeline still produces a valid result; this only proves
      // the btc spec was actually used (not silently ignored) via a
      // regression check: an unknown model name must fail the same way.
      expect(result.chords, isNotEmpty);
      expect(result.key, matches(_keyPattern));

      await expectLater(
        analyzer.analyze('testid', modelName: 'not_a_real_model'),
        throwsArgumentError,
      );
    });
  });

  group('DefaultSongRepository.generate (on-device wiring)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persists the on-device analysis and returns a valid AnalysisResult', () async {
      final analyzer = OnDeviceAnalyzer(audioSource: _FixturePcmAudioSource(fixturePcm));
      final local = LocalStore();
      final repo = DefaultSongRepository(_ThrowingApi(), local, analyzer);

      final result = await repo.generate('song123', title: 'My Song');

      expect(result.songId, 'song123');
      expect(result.source.title, 'My Song');
      expect(result.chords, isNotEmpty);
      expect(result.beats, isNotEmpty);

      // Persisted: a fresh get() (server throws, falls back to local) finds it.
      final fetched = await repo.get('song123');
      expect(fetched.songId, 'song123');
      expect(fetched.chords.length, result.chords.length);
    });

    test('passes the selected chord model through to the analyzer', () async {
      String? seenModelName;
      final analyzer = _RecordingAnalyzer(fixturePcm, (name) => seenModelName = name);
      final local = LocalStore();
      final repo = DefaultSongRepository(_ThrowingApi(), local, analyzer, () => 'btc');

      await repo.generate('song456');

      expect(seenModelName, 'btc');
    });
  });
}

/// Wraps a real OnDeviceAnalyzer over fixture PCM but records the
/// `modelName` it was called with, so tests can assert
/// DefaultSongRepository.generate actually forwards the selected model
/// (rather than always using the registry default).
class _RecordingAnalyzer extends OnDeviceAnalyzer {
  _RecordingAnalyzer(Float32List pcm, this._onModelName)
      : super(audioSource: _FixturePcmAudioSource(pcm));
  final void Function(String? modelName) _onModelName;

  @override
  Future<Map<String, dynamic>> analyze(String youtubeId, {String? title, String? modelName}) {
    _onModelName(modelName);
    return super.analyze(youtubeId, title: title, modelName: modelName);
  }
}

/// A ChordMindApi stand-in whose `get` always fails, forcing
/// SongRepository.get to fall back to the local store (mirrors the "server
/// offline" path already exercised by DefaultSongRepository.get).
class _ThrowingApi extends ChordMindApi {
  _ThrowingApi() : super(Dio());

  @override
  Future<AnalysisResult> get(String youtubeId) async => throw StateError('no server in tests');
}
