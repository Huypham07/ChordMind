import 'dart:math' as math;
import 'dart:typed_data';
import 'onset.dart';
import 'tempo.dart';

/// Beat times (seconds, ascending) plus the estimated global tempo (BPM).
class BeatResult {
  final List<double> beats;
  final double bpm;
  const BeatResult(this.beats, this.bpm);
}

/// Swappable so a future Beat-Transformer (ONNX) backend can replace the DSP
/// tracker without touching OnDeviceAnalyzer.
abstract interface class BeatTracker {
  BeatResult track(Float32List pcm, {double sr});
}

/// Pure-DSP beat tracker: spectral-flux onset → autocorrelation tempo →
/// Ellis (2007) dynamic-programming beat tracking (librosa's default).
class DspBeatTracker implements BeatTracker {
  const DspBeatTracker();

  @override
  BeatResult track(Float32List pcm, {double sr = 22050}) {
    final onset = onsetEnvelope(pcm);
    final bpm = estimateTempo(onset);
    if (bpm <= 0) return const BeatResult([], 0);

    final period = 60 * onsetFps / bpm; // beat period in onset frames
    final beatFrames = _dpBeats(onset, period);
    if (beatFrames.length < 2) return const BeatResult([], 0);

    final beats = [for (final f in beatFrames) f / onsetFps];
    return BeatResult(beats, bpm);
  }

  /// Ellis dynamic-programming beat tracker over the onset envelope.
  /// tightness controls how strongly deviations from `period` are penalized.
  List<int> _dpBeats(List<double> localscore, double period, {double tightness = 100}) {
    final n = localscore.length;
    if (n < 3 || period < 1) return const [];

    final backlink = List<int>.filled(n, -1);
    final cumscore = List<double>.filled(n, 0);

    // Predecessor window: offsets [-2*period, -period/2].
    final loOff = (-2 * period).round();
    final hiOff = (-period / 2).round();

    for (var i = 0; i < n; i++) {
      var bestScore = double.negativeInfinity;
      var bestPrev = -1;
      for (var off = loOff; off <= hiOff; off++) {
        final j = i + off;
        if (j < 0) continue;
        // Penalty grows with squared log-deviation from one period.
        final dev = math.log(-off / period);
        final txcost = -tightness * dev * dev;
        final score = cumscore[j] + txcost;
        if (score > bestScore) {
          bestScore = score;
          bestPrev = j;
        }
      }
      if (bestPrev < 0) {
        cumscore[i] = localscore[i];
        backlink[i] = -1;
      } else {
        cumscore[i] = localscore[i] + bestScore;
        backlink[i] = bestPrev;
      }
    }

    // Start backtrace from the best-scoring frame in the last period.
    var tail = -1;
    var tailScore = double.negativeInfinity;
    final searchFrom = math.max(0, n - period.round());
    for (var i = searchFrom; i < n; i++) {
      if (cumscore[i] > tailScore) {
        tailScore = cumscore[i];
        tail = i;
      }
    }
    if (tail < 0) return const [];

    final beats = <int>[];
    for (var i = tail; i >= 0; i = backlink[i]) {
      beats.add(i);
      if (backlink[i] < 0) break;
    }
    return beats.reversed.toList();
  }
}
