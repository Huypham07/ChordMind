import 'dart:math' as math;
import 'onset.dart';

/// Estimates global tempo (BPM) from an onset envelope via autocorrelation,
/// weighted by a log-normal prior centred on [priorBpm] (librosa's default
/// tempo prior). Searches 40–240 BPM. Returns 0.0 when the envelope has no
/// usable periodicity (flat/too short).
double estimateTempo(List<double> onset, {double fps = onsetFps, double priorBpm = 120}) {
  final n = onset.length;
  if (n < 4) return 0.0;

  // Autocorrelation over the lag range spanning 40–240 BPM.
  final minLag = math.max(1, (fps * 60 / 240).round());
  final maxLag = math.min(n - 1, (fps * 60 / 40).round());
  if (maxLag <= minLag) return 0.0;

  var bestBpm = 0.0;
  var bestScore = double.negativeInfinity;
  const stdOctaves = 1.0; // log-normal spread (in octaves) of the prior
  for (var lag = minLag; lag <= maxLag; lag++) {
    var ac = 0.0;
    for (var i = lag; i < n; i++) {
      ac += onset[i] * onset[i - lag];
    }
    final bpm = 60 * fps / lag;
    // Log-normal prior weight around priorBpm.
    final z = math.log(bpm / priorBpm) / math.ln2 / stdOctaves;
    final weight = math.exp(-0.5 * z * z);
    final score = ac * weight;
    if (score > bestScore) {
      bestScore = score;
      bestBpm = bpm;
    }
  }
  return bestScore > 0 ? bestBpm : 0.0;
}
