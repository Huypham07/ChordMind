import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/features/chord_grid/grid_sync.dart';

AnalysisResult _r() => AnalysisResult.fromJson({
      'songId': 'a', 'key': 'C major',
      'source': {'youtubeId': 'a', 'title': 'T', 'duration': 4.0, 'bpm': 120.0, 'timeSignature': 4},
      'beats': [], 'downbeats': [],
      'chords': [
        {'chord': 'C', 'start': 0.0, 'end': 2.0, 'confidence': 1.0},
        {'chord': 'G', 'start': 2.0, 'end': 4.0, 'confidence': 1.0},
      ],
      'synchronizedChords': [
        {'chord': 'C', 'beatIndex': 0},
        {'chord': 'G', 'beatIndex': 2},
      ],
      'segments': [],
    });

void main() {
  test('activeChordIndex maps position to chord cell', () {
    final r = _r();
    expect(activeChordIndex(r, 0.5), 0);
    expect(activeChordIndex(r, 2.5), 1);
    expect(activeChordIndex(r, -1.0), -1);
  });
}
