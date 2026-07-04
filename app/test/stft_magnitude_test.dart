import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/hybrid_cqt.dart';

void main() {
  test('stftMagnitude peaks at the bin of a pure sine', () {
    const nFft = 2048, hop = 512, sr = 22050.0;
    const freq = 1723.0; // ~ bin 160 at these params (160*sr/nFft ≈ 1723)
    final y = Float64List(sr ~/ 1); // 1 second
    for (var i = 0; i < y.length; i++) {
      y[i] = math.sin(2 * math.pi * freq * i / sr);
    }
    final mag = stftMagnitude(y, nFft: nFft, hop: hop);
    expect(mag, isNotEmpty);
    // Take a middle frame (away from zero-padded edges) and find its peak bin.
    final frame = mag[mag.length ~/ 2];
    var peak = 0;
    for (var f = 1; f < frame.length; f++) {
      if (frame[f] > frame[peak]) peak = f;
    }
    final expectedBin = (freq * nFft / sr).round(); // 160
    expect((peak - expectedBin).abs(), lessThanOrEqualTo(1));
  });
}
