import 'package:chordmind/core/models.dart';

/// Index into [r.beats] of the beat sounding at [pos] seconds, or -1.
/// Each beat spans from its time to the next beat's time (last → song end).
int activeBeatIndex(AnalysisResult r, double pos) {
  final b = r.beats;
  for (var i = 0; i < b.length; i++) {
    final end = (i + 1 < b.length) ? b[i + 1].time : r.source.duration;
    if (pos >= b[i].time && pos < end) return i;
  }
  return -1;
}

/// Index into [r.synchronizedChords] of the cell sounding at [pos] seconds, or -1.
/// Each cell spans from its beat time to the next cell's beat time
/// (the last cell extends to the song's end).
int activeChordIndex(AnalysisResult r, double pos) {
  final cells = r.synchronizedChords;
  for (var i = 0; i < cells.length; i++) {
    final start = r.beats[cells[i].beatIndex].time;
    final end = (i + 1 < cells.length)
        ? r.beats[cells[i + 1].beatIndex].time
        : r.source.duration;
    if (pos >= start && pos < end) return i;
  }
  return -1;
}
