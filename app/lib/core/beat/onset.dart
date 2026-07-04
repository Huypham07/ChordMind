import 'dart:typed_data';
import '../hybrid_cqt.dart';

/// Onset-envelope frame rate (frames/sec) for the default hop of 512 @ 22050 Hz.
const double onsetFps = 22050 / 512;

/// Spectral-flux onset envelope: per STFT frame, the sum over bins of the
/// positive magnitude increase vs the previous frame, max-normalized to
/// [0, 1]. `result[0]` is 0 (no predecessor). All-zero for silence.
List<double> onsetEnvelope(Float32List pcm, {int nFft = 2048, int hop = 512}) {
  final mag = stftMagnitude(Float64List.fromList(pcm), nFft: nFft, hop: hop);
  final n = mag.length;
  final env = List<double>.filled(n, 0.0);
  var maxV = 0.0;
  for (var t = 1; t < n; t++) {
    final cur = mag[t], prev = mag[t - 1];
    var flux = 0.0;
    for (var f = 0; f < cur.length; f++) {
      final d = cur[f] - prev[f];
      if (d > 0) flux += d;
    }
    env[t] = flux;
    if (flux > maxV) maxV = flux;
  }
  if (maxV > 0) {
    for (var t = 0; t < n; t++) {
      env[t] /= maxV;
    }
  }
  return env;
}
