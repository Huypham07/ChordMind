// Spike test for Plan B Task B0.1: prove the `onnxruntime` Dart package
// loads our exported chord ONNX models and produces outputs matching a
// Python (onnxruntime) reference for the same input.
//
// Reference vectors are pre-computed by
// scripts/export/.venv/bin/python against the ONNX files in
// artifacts/onnx/ (see app/test/fixtures/*_ref.json + *.bin, generated
// with a fixed numpy seed for reproducibility). This test loads the
// actual 47MB/1.9MB .onnx files by absolute path (not bundled as test
// fixtures) and re-runs them via the onnxruntime Dart FFI bindings.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime/onnxruntime.dart';

const _onnxDir = '/Users/huypham/code/ChordMind/artifacts/onnx';
const _fixturesDir = 'test/fixtures';

Float32List _readF32(String path) {
  final bytes = File(path).readAsBytesSync();
  return bytes.buffer.asFloat32List(
    bytes.offsetInBytes,
    bytes.lengthInBytes ~/ 4,
  );
}

double _maxAbsDiff(Float32List a, Float32List b) {
  expect(a.length, b.length);
  var maxDiff = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > maxDiff) maxDiff = d;
  }
  return maxDiff;
}

/// Argmax over the last axis of a flat row-major array.
List<int> _argmaxRows(Float32List flat, int rows, int cols) {
  final out = List<int>.filled(rows, 0);
  for (var r = 0; r < rows; r++) {
    var best = 0;
    var bestVal = flat[r * cols];
    for (var c = 1; c < cols; c++) {
      final v = flat[r * cols + c];
      if (v > bestVal) {
        bestVal = v;
        best = c;
      }
    }
    out[r] = best;
  }
  return out;
}

void main() {
  setUpAll(() {
    OrtEnv.instance.init();
  });

  tearDownAll(() {
    OrtEnv.instance.release();
  });

  test('chordnet_2e1d.onnx matches python onnxruntime reference', () {
    final refJson = jsonDecode(
      File('$_fixturesDir/chordnet_2e1d_ref.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final inputShape = (refJson['input_shape'] as List).cast<int>();
    final outputShape = (refJson['output_shape'] as List).cast<int>();
    final inputName = refJson['input_name'] as String;
    final refArgmax = (refJson['argmax'] as List).cast<int>();

    final input = _readF32('$_fixturesDir/${refJson['input_file']}');
    final refOutput = _readF32('$_fixturesDir/${refJson['output_file']}');

    final sessionOptions = OrtSessionOptions();
    final session = OrtSession.fromFile(
      File('$_onnxDir/chordnet_2e1d.onnx'),
      sessionOptions,
    );

    final inputOrt = OrtValueTensor.createTensorWithDataList(
      input,
      inputShape,
    );
    final runOptions = OrtRunOptions();
    final outputs = session.run(runOptions, {inputName: inputOrt});

    final outTensor = outputs[0] as OrtValueTensor;
    final outFlat = Float32List.fromList(
      (outTensor.value as List)
          .expand((e) => (e as List).expand((f) => f as List))
          .cast<double>()
          .toList(),
    );

    final maxDiff = _maxAbsDiff(outFlat, refOutput);
    // ignore: avoid_print
    print('chordnet_2e1d max abs diff: $maxDiff');
    expect(maxDiff, lessThan(1e-3));

    final seqLen = outputShape[1];
    final nClasses = outputShape[2];
    final dartArgmax = _argmaxRows(outFlat, seqLen, nClasses);
    expect(dartArgmax, refArgmax);

    inputOrt.release();
    runOptions.release();
    for (final o in outputs) {
      o?.release();
    }
    session.release();
    sessionOptions.release();
  });

  test('chord_cnn_lstm.onnx matches python onnxruntime reference', () {
    final refJson = jsonDecode(
      File('$_fixturesDir/chord_cnn_lstm_ref.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final inputShape = (refJson['input_shape'] as List).cast<int>();
    final inputName = refJson['input_name'] as String;
    final refOutputs = (refJson['outputs'] as List).cast<Map<String, dynamic>>();

    final input = _readF32('$_fixturesDir/${refJson['input_file']}');

    final sessionOptions = OrtSessionOptions();
    final session = OrtSession.fromFile(
      File('$_onnxDir/chord_cnn_lstm.onnx'),
      sessionOptions,
    );

    final inputOrt = OrtValueTensor.createTensorWithDataList(
      input,
      inputShape,
    );
    final runOptions = OrtRunOptions();
    final outputs = session.run(runOptions, {inputName: inputOrt});

    expect(outputs.length, refOutputs.length);
    expect(session.outputNames, refOutputs.map((o) => o['name']).toList());

    for (var i = 0; i < outputs.length; i++) {
      final refSpec = refOutputs[i];
      final shape = (refSpec['shape'] as List).cast<int>();
      final refArgmax = (refSpec['argmax'] as List).cast<int>();
      final refOut = _readF32('$_fixturesDir/${refSpec['file']}');

      final outTensor = outputs[i] as OrtValueTensor;
      final outFlat = Float32List.fromList(
        (outTensor.value as List)
            .expand((e) => e as List)
            .cast<double>()
            .toList(),
      );

      final maxDiff = _maxAbsDiff(outFlat, refOut);
      // ignore: avoid_print
      print('chord_cnn_lstm[${refSpec['name']}] max abs diff: $maxDiff');
      expect(maxDiff, lessThan(1e-3));

      final dartArgmax = _argmaxRows(outFlat, shape[0], shape[1]);
      expect(dartArgmax, refArgmax);
    }

    inputOrt.release();
    runOptions.release();
    for (final o in outputs) {
      o?.release();
    }
    session.release();
    sessionOptions.release();
  });
}
