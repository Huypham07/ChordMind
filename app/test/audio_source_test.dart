// Spike test for Plan B Task B0.2: prove youtubeId -> mono 22050 Hz float32
// PCM is achievable on-device via youtube_explode_dart (stream fetch) +
// a decoder (ffmpeg) turning compressed audio into raw PCM.
//
// This test uses the HOST-FFMPEG decoder stand-in (shells out to the host
// `ffmpeg` binary) to validate the WHOLE pipeline end-to-end without a
// device. The real Android/iOS path uses `FfmpegKitAudioDecoder` (native
// ffmpeg_kit_flutter_new), which requires a device/Gradle build and is not
// exercised here — same class of limitation as the onnxruntime dylib in
// B0.1's onnx_smoke_test.dart.
//
// Requires network access to YouTube and a host `ffmpeg` binary.
import 'dart:io';

import 'package:chordmind/core/audio_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// Short (few-second) videos, tried in order in case one is unavailable.
const _candidateIds = [
  'jNQXAC9IVRw', // "Me at the zoo" — first YouTube video, ~19s
  'BZmvOvGpHKA', // fallback: short clip
];

void main() {
  test(
    'AudioSource.pcm: youtubeId -> mono 22050 Hz PCM (host-ffmpeg proof)',
    () async {
      final decoder = HostFfmpegAudioDecoder(ffmpegPath: '/opt/homebrew/bin/ffmpeg');
      final source = AudioSource(decoder: decoder);

      Object? lastError;
      for (final id in _candidateIds) {
        try {
          final yt = YoutubeExplode();
          final video = await yt.videos.get(id);
          final duration = video.duration ?? Duration.zero;
          yt.close();

          final stopwatch = Stopwatch()..start();
          final pcm = await source.pcm(id);
          stopwatch.stop();

          expect(pcm, isNotEmpty);

          final expectedLen = duration.inMilliseconds / 1000 * kPcmSampleRate;
          final tolerance = expectedLen * 0.15 + kPcmSampleRate; // 15% + 1s
          expect(
            (pcm.length - expectedLen).abs(),
            lessThan(tolerance),
            reason:
                'pcm.length=${pcm.length} vs expected~$expectedLen '
                '(duration=${duration.inSeconds}s)',
          );

          var allZero = true;
          for (final v in pcm) {
            expect(v, greaterThanOrEqualTo(-1.0001));
            expect(v, lessThanOrEqualTo(1.0001));
            if (v != 0.0) allZero = false;
          }
          expect(allZero, isFalse, reason: 'PCM buffer is all zero');

          // ignore: avoid_print
          print(
            'id=$id duration=${duration.inSeconds}s '
            'samples=${pcm.length} (~${(pcm.length / kPcmSampleRate).toStringAsFixed(2)}s @ ${kPcmSampleRate}Hz) '
            'decode_wall_ms=${stopwatch.elapsedMilliseconds}',
          );
          return; // success on this id
        } catch (e) {
          lastError = e;
          // ignore: avoid_print
          print('id=$id failed: $e — trying next candidate if any');
        }
      }
      fail('all candidate YouTube ids failed; last error: $lastError');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('host ffmpeg binary is present (sanity)', () async {
    final result = await Process.run('/opt/homebrew/bin/ffmpeg', ['-version']);
    expect(result.exitCode, 0);
  });
}
