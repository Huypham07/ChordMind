import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/features/diagrams/voicings.dart';

void main() {
  test('common chords have 6-string voicings', () {
    expect(guitarVoicings['C']!.frets.length, 6);
    expect(guitarVoicings['G']!.frets.length, 6);
  });
  test('pianoNotes returns triad for major and minor', () {
    expect(pianoNotes('C'), [0, 4, 7]);   // C E G
    expect(pianoNotes('Am'), [9, 0, 4]);  // A C E
  });
}
