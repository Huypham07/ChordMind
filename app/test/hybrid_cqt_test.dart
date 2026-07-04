// Spike test for Plan B Task B0.3: reproduce librosa's `hybrid_cqt` feature
// (as chord-cnn-lstm expects it) natively in Dart, and check that feeding
// the Dart-computed feature into the real `chord_cnn_lstm.onnx` (via the
// onnxruntime Dart FFI bindings established in B0.1) preserves the 6-head
// argmax vs. the Python reference (`scripts/export/load_ccl.py:_cqt_v2`
// -> `net.inference`), on both spike fixtures.
//
// See app/lib/core/hybrid_cqt.dart for the algorithm + the deliberate
// approximation (a simple half-band FIR instead of librosa's soxr_hq
// resampler for the octave-recursion downsampling).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime/onnxruntime.dart';

import 'package:chordmind/core/hybrid_cqt.dart';

const _onnxDir = '/Users/huypham/code/ChordMind/artifacts/onnx';
const _fixturesDir = 'test/fixtures';
const _headNames = [
  'triad',
  'bass',
  'seventh',
  'ninth',
  'eleventh',
  'thirteenth',
];

Float64List _readPcm(String path) {
  final bytes = File(path).readAsBytesSync();
  final f32 = bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 4);
  final out = Float64List(f32.length);
  for (var i = 0; i < f32.length; i++) {
    out[i] = f32[i];
  }
  return out;
}

/// Runs chord_cnn_lstm.onnx on a [frames, 288] feature and returns the
/// per-head argmax (each a List<int> of length `frames`).
Map<String, List<int>> _runCclArgmax(
  OrtSession session,
  Float32List feature,
  int nFrames,
) {
  final sessionOptions = OrtSessionOptions();
  final inputOrt = OrtValueTensor.createTensorWithDataList(
    feature,
    [nFrames, 288],
  );
  final runOptions = OrtRunOptions();
  final outputs = session.run(runOptions, {'feature': inputOrt});

  final result = <String, List<int>>{};
  for (var i = 0; i < outputs.length; i++) {
    final outTensor = outputs[i] as OrtValueTensor;
    final nested = outTensor.value as List;
    final argmax = <int>[];
    for (final row in nested) {
      final r = (row as List).cast<double>();
      var best = 0;
      var bestVal = r[0];
      for (var c = 1; c < r.length; c++) {
        if (r[c] > bestVal) {
          bestVal = r[c];
          best = c;
        }
      }
      argmax.add(best);
    }
    result[session.outputNames[i]] = argmax;
  }

  inputOrt.release();
  runOptions.release();
  for (final o in outputs) {
    o?.release();
  }
  sessionOptions.release();
  return result;
}

double _agreement(List<int> a, List<int> b) {
  final n = a.length < b.length ? a.length : b.length;
  var match = 0;
  for (var i = 0; i < n; i++) {
    if (a[i] == b[i]) match++;
  }
  return match / n;
}

void main() {
  setUpAll(() {
    OrtEnv.instance.init();
  });

  tearDownAll(() {
    OrtEnv.instance.release();
  });

  for (final fixture in ['triad_cmaj', 'extended_c9']) {
    test('hybridCqt native feature vs python reference on $fixture', () {
      final refJson = jsonDecode(
        File('$_fixturesDir/hybrid_cqt_${fixture}_ref.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final refArgmax =
          (refJson['argmax'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as List).cast<int>()),
      );
      final featureShape = (refJson['feature_shape'] as List).cast<int>();
      final refNFrames = featureShape[0];

      final pcm = _readPcm('$_fixturesDir/hybrid_cqt_${fixture}_pcm.bin');
      final dartFeature = hybridCqt(pcm);
      final dartNFrames = dartFeature.length ~/ 288;

      // ignore: avoid_print
      print(
        '$fixture: python ref frames=$refNFrames, dart frames=$dartNFrames',
      );

      final sessionOptions = OrtSessionOptions();
      final session = OrtSession.fromFile(
        File('$_onnxDir/chord_cnn_lstm.onnx'),
        sessionOptions,
      );

      final dartArgmax = _runCclArgmax(session, dartFeature, dartNFrames);

      // ignore: avoid_print
      print('$fixture per-head argmax agreement (Dart feature vs python-ref argmax):');
      final agreements = <String, double>{};
      for (final name in _headNames) {
        final agree = _agreement(refArgmax[name]!, dartArgmax[name]!);
        agreements[name] = agree;
        // ignore: avoid_print
        print('  $name: $agree');
      }

      session.release();
      sessionOptions.release();

      // This is the task's stated gate. On the harder extended_c9 fixture
      // this spike does NOT reach it on every head -- see
      // .superpowers/sdd/task-b03-report.md for the honest breakdown and
      // diagnosis. We assert the real target rather than a lowered one so
      // this test's pass/fail state matches the actual achieved fidelity.
      for (final name in _headNames) {
        expect(
          agreements[name],
          greaterThanOrEqualTo(0.99),
          reason: 'head $name agreement below the 0.99 target: ${agreements[name]}',
        );
      }
    });
  }
}
