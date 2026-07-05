// app/test/decode/beat_sync_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/model_registry.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/inference/pcm_runner.dart';
import 'package:chordmind/core/decode/beat_sync.dart';

const _frameDur = 2048 / 22050;

ModelSpec _spec(List<String> labels) => ModelSpec.fromJson({
      'name': 'fake', 'file': 'fake.onnx', 'fs': 22050,
      'decode': 'vote', 'labels': labels, 'sha256': 'deadbeef',
    });

List<FrameResult> _frames(List<int> classIds) => [
      for (var i = 0; i < classIds.length; i++)
        FrameResult(frameIndex: i, classId: classIds[i], confidence: 1.0, time: i * _frameDur),
    ];

void main() {
  // labels: 0->N, 1->C, 2->G
  final spec = _spec(['N', 'C', 'G']);

  test('one chord per beat interval by majority (mode) of frames', () {
    // 12 frames; beats every 4 frames ⇒ intervals [0,4)[4,8)[8,end).
    // Interval 0 mostly C, interval 1 mostly G, interval 2 mostly C.
    final frames = _frames([1, 1, 1, 2, 2, 2, 2, 1, 1, 1, 1, 2]);
    final beats = [0.0, 4 * _frameDur, 8 * _frameDur];
    final chords = beatSyncChords(frames, beats, spec);
    expect(chords.map((c) => c.chord).toList(), ['C', 'G', 'C']);
    // Gap-free, covers the whole span.
    expect(chords.first.start, 0.0);
    for (var i = 1; i < chords.length; i++) {
      expect(chords[i].start, closeTo(chords[i - 1].end, 1e-9));
    }
    expect(chords.last.end, closeTo(12 * _frameDur, 1e-9));
  });

  test('consecutive equal beat labels merge into one chord', () {
    final frames = _frames([1, 1, 1, 1, 1, 1, 1, 1]); // all C
    final beats = [0.0, 4 * _frameDur];
    final chords = beatSyncChords(frames, beats, spec);
    expect(chords, hasLength(1));
    expect(chords.single.chord, 'C');
    expect(chords.single.end, closeTo(8 * _frameDur, 1e-9));
  });

  test('empty beats or empty frames returns empty (caller falls back)', () {
    expect(beatSyncChords(_frames([1, 2]), const [], spec), isEmpty);
    expect(beatSyncChords(const [], [0.0, 1.0], spec), isEmpty);
  });

  test('empty first interval falls back to the real N label, not labels[0]',
      () {
    // labels: 0->C, 1->G, 2->N (N is deliberately NOT at index 0).
    final specNNotFirst = _spec(['C', 'G', 'N']);
    // All frames start at frame index 2 (time = 2*_frameDur), so the lead-in
    // interval [0, 2*_frameDur) — created because beatTimes.first > 0 — has
    // no frames in it and must fall back to 'N', not labels[0] ('C').
    final frames = [
      for (var i = 2; i < 6; i++)
        FrameResult(frameIndex: i, classId: 0, confidence: 1.0, time: i * _frameDur),
    ];
    final beats = [2 * _frameDur, 6 * _frameDur];
    final chords = beatSyncChords(frames, beats, specNNotFirst);
    expect(chords.first.chord, 'N');
    expect(chords.first.start, 0.0);
    expect(chords.first.end, closeTo(2 * _frameDur, 1e-9));
  });
}
