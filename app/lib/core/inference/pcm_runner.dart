// app/lib/core/inference/pcm_runner.dart
//
// Plan B Task B1.2: slides a PCM-in chord model (chordnet_2e1d / btc; see
// ModelSpec.input == 'pcm') over a whole song's PCM in non-overlapping
// windows of `spec.windowSamples`, and collects per-frame argmax
// predictions across the entire song.
//
// Frame accounting: each window produces a fixed number of frames
// (`framesPerWindow`, read off the model's actual output shape — never
// hardcoded) covering `windowSamples` samples. The effective hop between
// frames within a window is therefore
//   hopLength = windowSamples ~/ (framesPerWindow - 1)
// (chordnet_2e1d/btc: 219136 ~/ 107 == 2048), and
//   frameDur = hopLength / fs
// (== 2048/22050 ~= 0.09288s). `time` for a frame is its GLOBAL index
// (across all windows, not just this window) times frameDur.
//
// The final window is short (song length isn't a multiple of
// windowSamples): it is zero-padded up to windowSamples before being fed
// to the model (the model requires a fixed-size input), but frames whose
// position falls entirely beyond the real (unpadded) audio are dropped
// from the result so trailing silence isn't emitted as bogus chords.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

import '../model_registry.dart';

/// One decoded frame's prediction: the argmax class over the model's
/// flat label set, its confidence, and its time offset into the song.
class FrameResult {
  /// Frame index across the whole song (window index * framesPerWindow +
  /// in-window index), monotonically increasing from 0.
  final int frameIndex;

  /// argmax class id into `ModelSpec.labels`.
  final int classId;

  /// Softmax-max confidence: softmax(logits)[classId], i.e.
  /// 1 / sum(exp(logit - maxLogit)) over the row. Not a raw/normalized
  /// logit value.
  final double confidence;

  /// Seconds from the start of the song: frameIndex * frameDur.
  final double time;

  FrameResult({
    required this.frameIndex,
    required this.classId,
    required this.confidence,
    required this.time,
  });
}

/// Runs a PCM-in chord model over an entire song's PCM by sliding
/// non-overlapping `windowSamples`-length windows, one ORT inference per
/// window.
class PcmInferenceRunner {
  final ModelSpec spec;
  OrtSession? _session;

  PcmInferenceRunner(this.spec) {
    if (spec.input != 'pcm') {
      throw ArgumentError(
        'PcmInferenceRunner requires a pcm-in model (got input=${spec.input} '
        'for ${spec.name})',
      );
    }
    if (spec.windowSamples == null) {
      throw ArgumentError('${spec.name} has no windowSamples in its manifest entry');
    }
  }

  Future<OrtSession> _ensureSession() async {
    final existing = _session;
    if (existing != null) return existing;
    final assetData = await rootBundle.load(spec.assetKey);
    final bytes = assetData.buffer.asUint8List(
      assetData.offsetInBytes,
      assetData.lengthInBytes,
    );
    final options = OrtSessionOptions();
    final session = OrtSession.fromBuffer(bytes, options);
    options.release();
    _session = session;
    return session;
  }

  /// Slides `spec.windowSamples`-length non-overlapping windows over
  /// [pcm] (mono float32 at `spec.fs`), running one ORT inference per
  /// window, and returns the per-frame argmax predictions for the whole
  /// song.
  Future<List<FrameResult>> run(Float32List pcm) async {
    final session = await _ensureSession();
    final windowSamples = spec.windowSamples!;
    final totalSamples = pcm.length;

    final results = <FrameResult>[];
    if (totalSamples == 0) return results;

    int? framesPerWindow;
    int? hopLength;
    double? frameDur;

    final runOptions = OrtRunOptions();
    var offset = 0;
    var globalFrameIndex = 0;
    try {
      while (offset < totalSamples) {
        final remaining = totalSamples - offset;
        final copyLen = remaining < windowSamples ? remaining : windowSamples;

        final window = Float32List(windowSamples); // zero-padded tail
        window.setRange(0, copyLen, pcm, offset);

        final inputTensor = OrtValueTensor.createTensorWithDataList(
          window,
          [1, windowSamples],
        );
        List<OrtValue?> outputs;
        try {
          outputs = session.run(runOptions, {'pcm': inputTensor});
        } finally {
          inputTensor.release();
        }

        try {
          final outTensor = outputs[0] as OrtValueTensor;
          // Shape [1, framesPerWindow, nClasses]; onnxruntime returns
          // nested Lists (batch -> frame -> class).
          final batch = outTensor.value as List;
          final seq = batch[0] as List; // [framesPerWindow][nClasses]

          framesPerWindow ??= seq.length;
          if (hopLength == null) {
            hopLength = windowSamples ~/ (framesPerWindow - 1);
            frameDur = hopLength / spec.fs;
          }

          int realFrames;
          if (copyLen < windowSamples) {
            realFrames = (copyLen / hopLength).ceil();
            if (realFrames > framesPerWindow) realFrames = framesPerWindow;
            if (realFrames < 0) realFrames = 0;
          } else {
            realFrames = framesPerWindow;
          }

          for (var f = 0; f < realFrames; f++) {
            final row = seq[f] as List;
            final nClasses = row.length;
            var bestIdx = 0;
            var bestVal = (row[0] as num).toDouble();
            for (var c = 1; c < nClasses; c++) {
              final v = (row[c] as num).toDouble();
              if (v > bestVal) {
                bestVal = v;
                bestIdx = c;
              }
            }
            // Softmax-max confidence (numerically stable: subtract the max
            // logit before exponentiating).
            var sumExp = 0.0;
            for (var c = 0; c < nClasses; c++) {
              sumExp += math.exp((row[c] as num).toDouble() - bestVal);
            }
            final confidence = 1.0 / sumExp;

            results.add(FrameResult(
              frameIndex: globalFrameIndex,
              classId: bestIdx,
              confidence: confidence,
              time: globalFrameIndex * frameDur!,
            ));
            globalFrameIndex++;
          }
        } finally {
          for (final o in outputs) {
            o?.release();
          }
        }

        offset += windowSamples;
      }
    } finally {
      runOptions.release();
    }

    return results;
  }

  /// Releases the ORT session. Safe to call multiple times.
  void dispose() {
    _session?.release();
    _session = null;
  }
}
