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

/// Decodes [frames] (a PCM-in "vote" model's per-frame argmax
/// predictions) into merged [Chord] segments, smoothing single-frame
/// flicker with a majority filter over an odd-sized [smoothingKernel]
/// (default 5).
List<Chord> voteDecode(
  List<FrameResult> frames,
  ModelSpec spec, {
  int smoothingKernel = 5,
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
  return chords;
}
