import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/transpose.dart';

void main() {
  test('transpose keeps suffix and slash bass', () {
    expect(transposeChord('C', 2, key: 'C major'), 'D');
    expect(transposeChord('Am', 3, key: 'A minor'), 'Cm');
    expect(transposeChord('F#m7', 1, key: 'C major'), 'Gm7');
    expect(transposeChord('C/E', 2, key: 'C major'), 'D/F#'); // D major → F#
    expect(transposeChord('G', 0, key: 'C major'), 'G'); // no-op
  });

  test('accidentals follow the resulting key', () {
    // C major +1 → Db major: black keys spell as flats
    expect(transposeChord('C', 1, key: 'C major'), 'Db');
    expect(transposeChord('G', 1, key: 'C major'), 'Ab'); // not G#
    // C major +2 → D major: sharps where diatonic
    expect(transposeChord('C', 2, key: 'C major'), 'D');
    // C major → Bb: pitch class 10 spelled Bb, not A#
    expect(transposeChord('C', 10, key: 'C major'), 'Bb');
    // Same pitch class, opposite spellings depending on key centre
    expect(transposeChord('C', 6, key: 'C major'), 'F#'); // #IV stays sharp
  });

  test('down transposition wraps and spells to key', () {
    expect(transposeChord('C', -1, key: 'C major'), 'B');
    expect(transposeChord('C', -2, key: 'C major'), 'Bb'); // Bb major-ish → flat
  });
}
