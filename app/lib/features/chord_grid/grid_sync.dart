import 'package:chordmind/core/models.dart';

int activeChordIndex(AnalysisResult r, double pos) {
  for (var i = 0; i < r.chords.length; i++) {
    if (pos >= r.chords[i].start && pos < r.chords[i].end) return i;
  }
  return -1;
}
