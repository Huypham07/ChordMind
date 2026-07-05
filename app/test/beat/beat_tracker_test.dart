import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/beat/beat_tracker.dart';

Float32List _clickTrack({double bpm = 120, double seconds = 10, int sr = 22050}) {
  final pcm = Float32List((seconds * sr).round());
  final periodSamples = (60 / bpm * sr).round();
  for (var s = 0; s < pcm.length; s += periodSamples) {
    // short decaying click so spectral flux sees a clear onset
    for (var k = 0; k < 64 && s + k < pcm.length; k++) {
      pcm[s + k] = (1.0 - k / 64) * (k.isEven ? 1.0 : -1.0);
    }
  }
  return pcm;
}

void main() {
  test('tracks ~120 BPM beats from a click track', () {
    final result = DspBeatTracker().track(_clickTrack(bpm: 120));
    expect(result.bpm, closeTo(120.0, 8.0));
    expect(result.beats.length, greaterThan(10));
    // Beats are ascending and spaced ~0.5s apart on average.
    for (var i = 1; i < result.beats.length; i++) {
      expect(result.beats[i], greaterThan(result.beats[i - 1]));
    }
    final span = result.beats.last - result.beats.first;
    final avg = span / (result.beats.length - 1);
    expect(avg, closeTo(0.5, 0.08));
  });

  test('too-short / silent input yields no beats', () {
    expect(DspBeatTracker().track(Float32List(2048)).beats, isEmpty);
    expect(DspBeatTracker().track(Float32List(22050 * 5)).beats, isEmpty);
  });
}
