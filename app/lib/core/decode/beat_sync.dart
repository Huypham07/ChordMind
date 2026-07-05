// Beat-synchronous chord decode: one chord per beat interval (mode of the
// model's per-frame class ids in that interval), consecutive equal labels
// merged. Anchoring chord changes to real beats removes sub-beat flicker
// (#5) and keeps the grid in sync with the audio (#4). Falls back to
// voteDecode (see on_device_analyzer) when there are no beats.
import '../inference/pcm_runner.dart';
import '../model_registry.dart';
import '../models.dart';
import 'vote_decode.dart' show fallbackFrameDur;

List<Chord> beatSyncChords(
  List<FrameResult> frames,
  List<double> beatTimes,
  ModelSpec spec,
) {
  if (frames.isEmpty || beatTimes.isEmpty) return const [];
  final labels = spec.labels;
  if (labels == null) {
    throw ArgumentError('${spec.name} has no labels in its manifest entry');
  }

  final nIndex = labels.indexOf('N'); // -1 if absent

  final frameDur =
      frames.length > 1 ? frames[1].time - frames[0].time : fallbackFrameDur;
  final songEnd = frames.last.time + frameDur;

  // Interval boundaries: optional lead-in from 0, the beats, then song end.
  final bounds = <double>[];
  if (beatTimes.first > 0) bounds.add(0.0);
  bounds.addAll(beatTimes);
  final end = songEnd > bounds.last ? songEnd : bounds.last + frameDur;
  bounds.add(end);

  // Walk frames once (both frames and bounds are ascending in time).
  final segments = <Chord>[];
  var fi = 0;
  var prevClass = -1;
  for (var b = 0; b + 1 < bounds.length; b++) {
    final lo = bounds[b], hi = bounds[b + 1];
    final counts = <int, int>{};
    final confSum = <int, double>{};
    while (fi < frames.length && frames[fi].time < hi) {
      if (frames[fi].time >= lo) {
        final c = frames[fi].classId;
        counts[c] = (counts[c] ?? 0) + 1;
        confSum[c] = (confSum[c] ?? 0) + frames[fi].confidence;
      }
      fi++;
    }

    int winner;
    double conf;
    if (counts.isEmpty) {
      // Empty interval: inherit the previous chord (or N for the first).
      winner = prevClass >= 0 ? prevClass : (nIndex >= 0 ? nIndex : 0);
      conf = 0.0;
    } else {
      winner = counts.keys.first;
      for (final c in counts.keys) {
        final better = counts[c]! > counts[winner]! ||
            (counts[c] == counts[winner] && confSum[c]! > confSum[winner]!);
        if (better) winner = c;
      }
      conf = confSum[winner]! / counts[winner]!;
    }
    prevClass = winner;

    // Merge into the previous segment if the label matches.
    if (segments.isNotEmpty && segments.last.chord == labels[winner]) {
      final prev = segments.removeLast();
      final prevDur = prev.end - prev.start;
      final curDur = hi - lo;
      segments.add(Chord.fromJson({
        'chord': prev.chord,
        'start': prev.start,
        'end': hi,
        'confidence':
            (prev.confidence * prevDur + conf * curDur) / (prevDur + curDur),
      }));
    } else {
      segments.add(Chord.fromJson({
        'chord': labels[winner], 'start': lo, 'end': hi, 'confidence': conf,
      }));
    }
  }
  return segments;
}
