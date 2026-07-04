// app/test/beat/tempo_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/beat/onset.dart';
import 'package:chordmind/core/beat/tempo.dart';

void main() {
  test('estimates 120 BPM from an onset pulsing every 0.5s', () {
    const fps = onsetFps;
    final n = (fps * 10).round(); // 10 seconds
    final period = (fps * 0.5).round(); // 0.5s ⇒ 120 BPM
    final onset = List<double>.filled(n, 0.0);
    for (var i = 0; i < n; i += period) {
      onset[i] = 1.0;
    }
    final bpm = estimateTempo(onset, fps: fps);
    expect(bpm, closeTo(120.0, 6.0));
  });

  test('returns 0 for a flat (no-onset) envelope', () {
    expect(estimateTempo(List<double>.filled(400, 0.0)), 0.0);
  });
}
