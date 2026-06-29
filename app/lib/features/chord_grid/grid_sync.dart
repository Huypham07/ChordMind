import 'package:chordmind/core/models.dart';

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
