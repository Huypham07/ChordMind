// app/lib/core/decode/vote_decode.dart
//
// Plan B Task B1.3: decodes a PCM-in "vote"-decoded model's per-frame
// argmax predictions (PcmInferenceRunner's List<FrameResult>) into merged
// Chord segments.
//
// Pipeline:
//   1. Map each frame's classId -> label via ModelSpec.labels.
//   2. Majority-filter smoothing over the class-id sequence (odd
//      smoothingKernel, default 5 ~= 0.46s at frame_dur ~= 0.09288s) to
//      remove single-frame flicker. This mirrors the reference
//      majority_filter_indices in
//      reference/ChordMini/src/evaluation/utils/common.py exactly,
//      including its tie rule and its "too-short sequence" no-op:
//        - edge-clamped window of size kernel (kernel forced odd, >=1).
//        - if the sequence is shorter than the kernel, no smoothing is
//          applied at all (matches reference: `values.size < kernel_size`
//          -> return the sequence unchanged).
//        - for each frame, take the most common class id in the centered,
//          edge-clamped window; on ties, keep the frame's own class if it
//          is among the tied max-count candidates, else take the smallest
//          such candidate (reference iterates candidates in ascending
//          label order and takes candidates[0]).
//   3. Merge consecutive equal smoothed labels into one Chord: start =
//      time of the first frame in the run, end = time of the last frame
//      in the run + frame_dur (frame_dur derived from the consecutive
//      frame time delta), confidence = mean confidence over the run.
//   4. 'N' (no-chord) and 'X' (unknown) runs are kept as Chords like any
//      other label -- never dropped -- so the decoded timeline has no
//      gaps.
import '../inference/pcm_runner.dart';
import '../model_registry.dart';
import '../models.dart';

/// Fallback frame duration (seconds) used only when fewer than 2 frames
/// are available, so a delta between consecutive frame times can't be
/// derived. Matches the PCM-in chordnet/btc hop (2048 samples @ 22050 Hz;
/// see pcm_runner.dart's frame accounting).
const fallbackFrameDur = 2048 / 22050;

/// Applies the reference `majority_filter_indices` categorical majority
/// filter to a sequence of class ids.
List<int> _majorityFilter(List<int> values, int kernelSize) {
  var kernel = kernelSize < 1 ? 1 : kernelSize;
  if (kernel % 2 == 0) kernel += 1;
  final n = values.length;
  if (kernel == 1 || n < kernel) {
    return List<int>.from(values);
  }

  final pad = kernel ~/ 2;
  int atPadded(int paddedIdx) {
    // Edge-clamped index into `values` for a virtual array with `pad`
    // edge-replicated entries on each side (np.pad mode='edge').
    final i = paddedIdx - pad;
    if (i < 0) return values[0];
    if (i >= n) return values[n - 1];
    return values[i];
  }

  final filtered = List<int>.filled(n, 0);
  for (var idx = 0; idx < n; idx++) {
    final counts = <int, int>{};
    for (var w = 0; w < kernel; w++) {
      final v = atPadded(idx + w);
      counts[v] = (counts[v] ?? 0) + 1;
    }
    var maxCount = 0;
    for (final c in counts.values) {
      if (c > maxCount) maxCount = c;
    }
    // Ascending label order, matching np.unique's sorted output.
    final candidates = counts.keys.where((k) => counts[k] == maxCount).toList()
      ..sort();
    final center = values[idx];
    filtered[idx] = candidates.contains(center) ? center : candidates.first;
  }
  return filtered;
}

/// Absorbs chord segments shorter than [minDur] seconds into a neighbor so
/// the timeline has no sub-[minDur] "junk" chords (e.g. a 1-frame D7 between
/// D and G). Repeatedly takes the shortest too-short segment and merges it
/// into its longer-duration neighbor (tie -> previous): the neighbor's label
/// wins, its span extends to cover the gap, confidence becomes the
/// duration-weighted mean. Applies uniformly to 'N'/'X' too. The timeline
/// stays gap-free (every span remains covered).
/// ponytail: O(n^2) scan, fine for song-length chord lists.
List<Chord> _mergeShort(List<Chord> chords, double minDur) {
  final out = List<Chord>.of(chords);
  while (out.length > 1) {
    // Find the shortest segment still under the threshold.
    var shortest = -1;
    var shortestDur = minDur;
    for (var i = 0; i < out.length; i++) {
      final d = out[i].end - out[i].start;
      if (d < shortestDur) {
        shortest = i;
        shortestDur = d;
      }
    }
    if (shortest < 0) break; // nothing left under minDur

    // Pick the longer-duration neighbor to absorb into (tie -> previous).
    final prev = shortest > 0 ? shortest - 1 : -1;
    final next = shortest < out.length - 1 ? shortest + 1 : -1;
    int keep;
    if (prev < 0) {
      keep = next;
    } else if (next < 0) {
      keep = prev;
    } else {
      final prevDur = out[prev].end - out[prev].start;
      final nextDur = out[next].end - out[next].start;
      keep = nextDur > prevDur ? next : prev;
    }

    final s = out[shortest];
    final k = out[keep];
    final sDur = s.end - s.start;
    final kDur = k.end - k.start;
    final conf = (k.confidence * kDur + s.confidence * sDur) / (kDur + sDur);
    out[keep] = Chord.fromJson({
      'chord': k.chord,
      'start': k.start < s.start ? k.start : s.start,
      'end': k.end > s.end ? k.end : s.end,
      'confidence': conf,
    });
    out.removeAt(shortest);

    // Absorbing may leave the kept segment adjacent to an equal label; merge.
    final ki = keep > shortest ? keep - 1 : keep;
    for (final j in [ki + 1, ki - 1]) {
      if (j >= 0 && j < out.length && out[j].chord == out[ki].chord) {
        final a = out[j < ki ? j : ki];
        final b = out[j < ki ? ki : j];
        final aDur = a.end - a.start;
        final bDur = b.end - b.start;
        out[j < ki ? j : ki] = Chord.fromJson({
          'chord': a.chord,
          'start': a.start,
          'end': b.end,
          'confidence':
              (a.confidence * aDur + b.confidence * bDur) / (aDur + bDur),
        });
        out.removeAt(j < ki ? ki : j);
        break;
      }
    }
  }
  return out;
}

/// Decodes [frames] (a PCM-in "vote" model's per-frame argmax
/// predictions) into merged [Chord] segments, smoothing single-frame
/// flicker with a majority filter over an odd-sized [smoothingKernel]
/// (default 5), then absorbing segments shorter than [minChordDur] seconds
/// into a neighbor so the timeline has no sub-[minChordDur] junk chords.
List<Chord> voteDecode(
  List<FrameResult> frames,
  ModelSpec spec, {
  int smoothingKernel = 5,
  double minChordDur = 0.3,
}) {
  if (frames.isEmpty) return [];

  final labels = spec.labels;
  if (labels == null) {
    throw ArgumentError('${spec.name} has no labels in its manifest entry');
  }

  final classIds = [for (final f in frames) f.classId];
  final smoothed = _majorityFilter(classIds, smoothingKernel);

  // frame_dur: consecutive frame time delta (0 if only one frame).
  final frameDur =
      frames.length > 1 ? frames[1].time - frames[0].time : fallbackFrameDur;

  final chords = <Chord>[];
  var runStart = 0;
  for (var i = 1; i <= frames.length; i++) {
    final atRunEnd = i == frames.length || smoothed[i] != smoothed[runStart];
    if (atRunEnd) {
      final runFrames = frames.sublist(runStart, i);
      var sumConf = 0.0;
      for (final f in runFrames) {
        sumConf += f.confidence;
      }
      chords.add(Chord.fromJson({
        'chord': labels[smoothed[runStart]],
        'start': runFrames.first.time,
        'end': runFrames.last.time + frameDur,
        'confidence': sumConf / runFrames.length,
      }));
      runStart = i;
    }
  }
  return _mergeShort(chords, minChordDur);
}
