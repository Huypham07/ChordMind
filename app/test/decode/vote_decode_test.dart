// Task B1.3: voteDecode smooths per-frame chord predictions with a
// majority filter (mirroring the reference
// reference/ChordMini/src/evaluation/utils/common.py:majority_filter_indices)
// and merges consecutive equal smoothed labels into Chord segments.
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/model_registry.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/inference/pcm_runner.dart';
import 'package:chordmind/core/decode/vote_decode.dart';

const _frameDur = 2048 / 22050; // matches vote_decode.dart's fallbackFrameDur

ModelSpec _spec(List<String> labels) {
  return ModelSpec.fromJson({
    'name': 'fake',
    'file': 'fake.onnx',
    'fs': 22050,
    'decode': 'vote',
    'labels': labels,
    'sha256': 'deadbeef',
  });
}

List<FrameResult> _frames(List<int> classIds, {List<double>? confidences}) {
  return [
    for (var i = 0; i < classIds.length; i++)
      FrameResult(
        frameIndex: i,
        classId: classIds[i],
        confidence: confidences != null ? confidences[i] : 1.0,
        time: i * _frameDur,
      ),
  ];
}

void main() {
  // labels: 0 -> 'N', 1 -> 'C', 2 -> 'G', 3 -> 'X'
  final labels = ['N', 'C', 'G', 'X'];

  test('empty input yields empty list', () {
    final spec = _spec(labels);
    expect(voteDecode([], spec), isEmpty);
  });

  test('single frame yields one chord spanning one frame_dur', () {
    final spec = _spec(labels);
    final frames = _frames([1]);
    final chords = voteDecode(frames, spec);
    expect(chords, hasLength(1));
    expect(chords[0].chord, 'C');
    expect(chords[0].start, 0.0);
    expect(chords[0].end, closeTo(_frameDur, 1e-9));
    expect(chords[0].confidence, closeTo(1.0, 1e-9));
  });

  test('consecutive equal frames merge into one Chord with correct bounds', () {
    final spec = _spec(labels);
    // 6 identical frames, kernel 5 default smoothing, no flicker so
    // smoothing is a no-op.
    final frames = _frames(List.filled(6, 1), confidences: [
      0.5, 0.6, 0.7, 0.8, 0.9, 1.0,
    ]);
    final chords = voteDecode(frames, spec);
    expect(chords, hasLength(1));
    expect(chords[0].chord, 'C');
    expect(chords[0].start, 0.0);
    expect(chords[0].end, closeTo(6 * _frameDur, 1e-9));
    expect(chords[0].confidence, closeTo((0.5 + 0.6 + 0.7 + 0.8 + 0.9 + 1.0) / 6, 1e-9));
  });

  test('single-frame flicker C C X C C is smoothed away (kernel 5)', () {
    final spec = _spec(labels);
    final frames = _frames([1, 1, 3, 1, 1]); // C C X C C
    final chords = voteDecode(frames, spec, smoothingKernel: 5);
    expect(chords, hasLength(1));
    expect(chords[0].chord, 'C');
    expect(chords[0].start, 0.0);
    expect(chords[0].end, closeTo(5 * _frameDur, 1e-9));
  });

  test('N runs produce N chords (not dropped); no gaps in timeline', () {
    final spec = _spec(labels);
    // N N N C C C N N N
    final frames = _frames([0, 0, 0, 1, 1, 1, 0, 0, 0]);
    // minChordDur: 0 isolates the smoothing/merge behavior from the
    // min-duration pass (each 3-frame run is ~0.28s, under the 0.3 default).
    final chords = voteDecode(frames, spec, minChordDur: 0);
    expect(chords.map((c) => c.chord).toList(), ['N', 'C', 'N']);
    for (var i = 1; i < chords.length; i++) {
      expect(chords[i].start, chords[i - 1].end);
    }
    expect(chords.first.start, 0.0);
    expect(chords.last.end, closeTo(9 * _frameDur, 1e-9));
  });

  test('X (unknown) passes through as its own chord like any other label', () {
    final spec = _spec(labels);
    // Long enough runs so the majority filter doesn't smooth the X away.
    final frames = _frames([1, 1, 1, 3, 3, 3, 3, 1, 1, 1]);
    final chords = voteDecode(frames, spec, minChordDur: 0);
    expect(chords.map((c) => c.chord).toList(), ['C', 'X', 'C']);
  });

  test('tie behavior matches reference majority_filter_indices: '
      'keep center if it is among the max-count candidates', () {
    final spec = _spec(labels);
    // Window (kernel 5, edge-clamped) centered at index 2 in
    // [0,0,1,2, ... ] with values 0,0,1,2,2 (pad edge on the left with the
    // first value 0). Sequence: [0, 0, 1, 2, 2, ...]. At idx=2 (value 1),
    // window (edge-padded) is indices [0,1,2,3,4] = [0,0,1,2,2]:
    // counts: 0->2, 1->1, 2->2. max_count=2, candidates=[0,2] (ascending).
    // center=1 is NOT in candidates -> filtered value = candidates[0] = 0.
    final frames = _frames([0, 0, 1, 2, 2, 2, 2, 2, 2, 2]);
    final chords = voteDecode(frames, spec, smoothingKernel: 5, minChordDur: 0);
    // idx=2's smoothed class becomes 0 ('N'), so it joins the leading N
    // run rather than starting its own 'C' segment.
    expect(chords.map((c) => c.chord).toList(), ['N', 'G']);
    expect(chords[0].start, 0.0);
    // N run covers idx 0,1,2 (3 frames) before G run starts.
    expect(chords[1].start, closeTo(3 * _frameDur, 1e-9));
  });

  test('tie behavior: center IS among candidates keeps the center value', () {
    final spec = _spec(labels);
    // idx=2 window edge-padded [0,0,1,1,2] (values [0,0,1,1,2,...] at
    // idx 2, pad-left with value 0): counts 0->2,1->2,2->1. max=2,
    // candidates=[0,1]. center=1 is in candidates -> stays 1.
    final frames = _frames([0, 0, 1, 1, 2, 2, 2, 2, 2, 2]);
    final chords = voteDecode(frames, spec, smoothingKernel: 5, minChordDur: 0);
    expect(chords.map((c) => c.chord).toList(), ['N', 'C', 'G']);
  });

  test('too-short sequence (< kernel size) is not smoothed at all', () {
    final spec = _spec(labels);
    // Reference: values.size < kernel_size -> return copy unmodified.
    final frames = _frames([1, 3, 1]); // C X C, only 3 frames, kernel 5
    final chords = voteDecode(frames, spec, smoothingKernel: 5, minChordDur: 0);
    expect(chords.map((c) => c.chord).toList(), ['C', 'X', 'C']);
  });

  // --- min-duration merge (issue #5) ---
  // kernel 1 disables smoothing so these isolate the min-duration pass.

  test('short junk segment is absorbed into the longer neighbor', () {
    final spec = _spec(labels);
    // C x5, X x1 (junk), G x5. X spans ~0.093s < 0.3 default -> absorbed.
    // Neighbors C(5) and G(5) tie -> previous (C) wins.
    final frames = _frames([1, 1, 1, 1, 1, 3, 2, 2, 2, 2, 2]);
    // Absorption mechanics tested at an explicit 0.3s threshold (independent
    // of the vote default). X spans ~0.093s -> absorbed; C(5)/G(5) tie -> C.
    final chords = voteDecode(frames, spec, smoothingKernel: 1, minChordDur: 0.3);
    expect(chords.map((c) => c.chord).toList(), ['C', 'G']);
    // Invariant: no segment shorter than the threshold survives.
    for (final c in chords) {
      expect(c.end - c.start, greaterThanOrEqualTo(0.3));
    }
    // Timeline stays gap-free and total span is preserved.
    for (var i = 1; i < chords.length; i++) {
      expect(chords[i].start, chords[i - 1].end);
    }
    expect(chords.first.start, 0.0);
    expect(chords.last.end, closeTo(11 * _frameDur, 1e-9));
  });

  test('absorbing a junk segment re-merges equal-label neighbors', () {
    final spec = _spec(labels);
    // C x5, X x1 (junk), C x5. X absorbed, leaving two C runs adjacent ->
    // merged into a single C spanning the whole timeline.
    final frames = _frames([1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1]);
    final chords = voteDecode(frames, spec, smoothingKernel: 1);
    expect(chords.map((c) => c.chord).toList(), ['C']);
    expect(chords.single.start, 0.0);
    expect(chords.single.end, closeTo(11 * _frameDur, 1e-9));
  });

  test('all segments too short: collapses without gaps or crash', () {
    final spec = _spec(labels);
    // Every 1-frame run is under threshold; merge until one segment remains.
    final frames = _frames([1, 2, 1, 2, 1]);
    final chords = voteDecode(frames, spec, smoothingKernel: 1);
    expect(chords, hasLength(1));
    expect(chords.single.start, 0.0);
    expect(chords.single.end, closeTo(5 * _frameDur, 1e-9));
  });
}
