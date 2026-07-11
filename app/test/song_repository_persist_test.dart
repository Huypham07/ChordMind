import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chordmind/core/api.dart';
import 'package:chordmind/core/audio_store.dart';
import 'package:chordmind/core/local_store.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/on_device_analyzer.dart';
import 'package:chordmind/core/song_repository.dart';

class _FakeAnalyzer extends OnDeviceAnalyzer {
  _FakeAnalyzer() : super();
  @override
  Future<Map<String, dynamic>> analyze(String youtubeId,
      {String? title, String? modelName, String? audioFilePath}) async {
    return {
      'songId': youtubeId, 'key': 'C major',
      'source': {'youtubeId': youtubeId, 'title': title ?? youtubeId, 'duration': 1.0, 'bpm': 120.0, 'timeSignature': 4},
      'beats': [], 'downbeats': [], 'chords': [], 'synchronizedChords': [], 'segments': [],
    };
  }
}

class _FakeAudioStore extends AudioStore {
  @override
  Future<String> persist(String songId, String srcPath) async => '/persisted/$songId.mp3';
}

class _ThrowingApi extends ChordMindApi {
  _ThrowingApi() : super(Dio());
  @override
  Future<AnalysisResult> get(String id) => throw Exception('offline');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('generate persists a file song and records source.audioPath', () async {
    final repo = DefaultSongRepository(
        _ThrowingApi(), LocalStore(), _FakeAnalyzer(), () => 'btc', _FakeAudioStore());

    final r = await repo.generate('file:x.mp3', title: 'X', audioFilePath: '/tmp/cache/x.mp3');
    expect(r.source.audioPath, '/persisted/file:x.mp3.mp3');

    // Persisted to local store too (fresh get falls back to local).
    final fetched = await repo.get('file:x.mp3');
    expect(fetched.source.audioPath, '/persisted/file:x.mp3.mp3');
  });

  test('generate for a YouTube song (no file) leaves audioPath null', () async {
    final repo = DefaultSongRepository(
        _ThrowingApi(), LocalStore(), _FakeAnalyzer(), () => 'btc', _FakeAudioStore());
    final r = await repo.generate('abcdefghijk', title: 'Y');
    expect(r.source.audioPath, isNull);
  });
}
