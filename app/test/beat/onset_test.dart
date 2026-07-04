// app/test/beat/onset_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/beat/onset.dart';

void main() {
  test('onset envelope spikes near an impulse and is quiet elsewhere', () {
    const sr = 22050, hop = 512;
    final pcm = Float32List(sr); // 1 second of silence
    final impulseSample = sr ~/ 2; // impulse at t=0.5s
    pcm[impulseSample] = 1.0;
    final env = onsetEnvelope(pcm, hop: hop);
    expect(env, isNotEmpty);
    expect(env.first, 0.0); // first frame has no predecessor
    // Frame nearest the impulse should carry the largest flux.
    final impulseFrame = (impulseSample / hop).round();
    var peak = 0;
    for (var i = 1; i < env.length; i++) {
      if (env[i] > env[peak]) peak = i;
    }
    expect((peak - impulseFrame).abs(), lessThanOrEqualTo(3));
    expect(env[peak], greaterThan(0.5)); // normalized, so the peak ≈ 1
  });

  test('silent input yields an all-zero envelope', () {
    final env = onsetEnvelope(Float32List(22050));
    expect(env.every((v) => v == 0.0), isTrue);
  });
}
