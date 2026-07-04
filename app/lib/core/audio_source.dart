/// YouTube id -> decoded mono 22050 Hz float32 PCM, on-device.
///
/// Two stages, kept separate so the decoder is swappable:
///   1. `youtube_explode_dart` (pure Dart, uses `http`) resolves the video's
///      audio-only stream manifest and downloads the smallest audio stream's
///      bytes (compressed, e.g. opus/m4a).
///   2. An [AudioDecoder] turns those compressed bytes into mono 22050 Hz
///      float32 PCM. Two implementations exist:
///        - [FfmpegKitAudioDecoder]: native decode via `ffmpeg_kit_flutter_new`
///          for the real Android/iOS app. Requires a device/Gradle build to
///          run — same class of limitation as the onnxruntime dylib in B0.1.
///          UNTESTED here (no device in this environment).
///        - [HostFfmpegAudioDecoder]: shells out to the host `ffmpeg` binary
///          via `dart:io Process.run`. This is a stand-in used ONLY to prove
///          the end-to-end pipeline on the host (`flutter test`); it is not
///          what ships to devices.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const int kPcmSampleRate = 22050;

/// Decodes arbitrary (compressed) audio bytes into mono PCM at [sampleRate].
abstract class AudioDecoder {
  Future<Float32List> toPcm(
    Uint8List bytes, {
    int sampleRate = kPcmSampleRate,
    bool mono = true,
  });
}

/// Native decode path for the real app (Android/iOS), via ffmpeg_kit.
/// Requires a device/Gradle build; not exercised by `flutter test` on host.
class FfmpegKitAudioDecoder implements AudioDecoder {
  @override
  Future<Float32List> toPcm(
    Uint8List bytes, {
    int sampleRate = kPcmSampleRate,
    bool mono = true,
  }) async {
    final tmpDir = await getTemporaryDirectory();
    final inPath = p.join(
      tmpDir.path,
      'audio_source_in_${DateTime.now().microsecondsSinceEpoch}',
    );
    final outPath = '$inPath.f32le.pcm';
    final inFile = File(inPath);
    await inFile.writeAsBytes(bytes, flush: true);
    try {
      final channels = mono ? 1 : 2;
      final session = await FFmpegKit.execute(
        '-y -i "$inPath" -f f32le -ac $channels -ar $sampleRate "$outPath"',
      );
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        throw StateError('ffmpeg_kit decode failed: $logs');
      }
      final outBytes = await File(outPath).readAsBytes();
      return outBytes.buffer.asFloat32List(
        outBytes.offsetInBytes,
        outBytes.lengthInBytes ~/ 4,
      );
    } finally {
      if (await inFile.exists()) await inFile.delete();
      final outFile = File(outPath);
      if (await outFile.exists()) await outFile.delete();
    }
  }
}

/// Host-testable stand-in: shells out to the host `ffmpeg` binary. Proves the
/// pipeline end-to-end in `flutter test` without a device/native plugin.
class HostFfmpegAudioDecoder implements AudioDecoder {
  HostFfmpegAudioDecoder({this.ffmpegPath = 'ffmpeg'});

  final String ffmpegPath;

  @override
  Future<Float32List> toPcm(
    Uint8List bytes, {
    int sampleRate = kPcmSampleRate,
    bool mono = true,
  }) async {
    final tmpDir = await Directory.systemTemp.createTemp('audio_source_');
    final inPath = p.join(tmpDir.path, 'in.audio');
    final outPath = p.join(tmpDir.path, 'out.f32le.pcm');
    await File(inPath).writeAsBytes(bytes, flush: true);
    try {
      final channels = mono ? '1' : '2';
      final result = await Process.run(ffmpegPath, [
        '-y',
        '-i', inPath,
        '-f', 'f32le',
        '-ac', channels,
        '-ar', '$sampleRate',
        outPath,
      ]);
      if (result.exitCode != 0) {
        throw StateError('host ffmpeg decode failed: ${result.stderr}');
      }
      final outBytes = await File(outPath).readAsBytes();
      return outBytes.buffer.asFloat32List(
        outBytes.offsetInBytes,
        outBytes.lengthInBytes ~/ 4,
      );
    } finally {
      await tmpDir.delete(recursive: true);
    }
  }
}

class AudioSource {
  AudioSource({AudioDecoder? decoder})
    : decoder = decoder ?? FfmpegKitAudioDecoder();

  final AudioDecoder decoder;

  /// From a YouTube video id, download the smallest audio-only stream and
  /// decode it to mono float32 PCM at [kPcmSampleRate].
  Future<Float32List> pcm(String youtubeId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(youtubeId);
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isEmpty) {
        throw StateError('no audio-only streams for $youtubeId');
      }
      final stream = audioStreams.sortByBitrate().first; // smallest
      final bytes = await yt.videos.streamsClient
          .get(stream)
          .fold<BytesBuilder>(
            BytesBuilder(),
            (b, chunk) => b..add(chunk),
          );
      return decoder.toPcm(bytes.takeBytes());
    } finally {
      yt.close();
    }
  }
}
