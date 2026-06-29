import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/features/chord_grid/grid_sync.dart';

AnalysisResult _r() => AnalysisResult.fromJson({
      'songId': 'a', 'key': 'C major',
      'source': {'youtubeId': 'a', 'title': 'T', 'duration': 4.0, 'bpm': 120.0, 'timeSignature': 4},
      'beats': [
        {'time': 0.0, 'beatNum': 1}, {'time': 0.5, 'beatNum': 2},
        {'time': 1.0, 'beatNum': 3}, {'time': 1.5, 'beatNum': 4},
        {'time': 2.0, 'beatNum': 1}, {'time': 2.5, 'beatNum': 2},
        {'time': 3.0, 'beatNum': 3}, {'time': 3.5, 'beatNum': 4},
      ],
      'downbeats': [0.0, 2.0],
      'chords': [
        {'chord': 'C', 'start': 0.0, 'end': 2.0, 'confidence': 1.0},
        {'chord': 'G', 'start': 2.0, 'end': 4.0, 'confidence': 1.0},
      ],
      'synchronizedChords': [
        {'chord': 'C', 'beatIndex': 0},
        {'chord': 'G', 'beatIndex': 4},
      ],
      'segments': [],
    });

AnalysisResult _empty() => AnalysisResult.fromJson({
      'songId': 'a', 'key': 'C major',
      'source': {'youtubeId': 'a', 'title': 'T', 'duration': 4.0, 'bpm': 120.0, 'timeSignature': 4},
      'beats': [], 'downbeats': [], 'chords': [], 'synchronizedChords': [], 'segments': [],
    });

void main() {
  test('activeChordIndex maps position to the right synchronizedChords cell', () {
    final r = _r();
    expect(activeChordIndex(r, 0.0), 0);   // boundary: exact start of cell 0
    expect(activeChordIndex(r, 0.5), 0);
    expect(activeChordIndex(r, 2.0), 1);   // boundary: exact start of cell 1
    expect(activeChordIndex(r, 2.5), 1);
    expect(activeChordIndex(r, 3.9), 1);   // last cell extends to duration
    expect(activeChordIndex(r, -1.0), -1); // before first
  });

  test('empty synchronizedChords returns -1', () {
    expect(activeChordIndex(_empty(), 1.0), -1);
  });
}
