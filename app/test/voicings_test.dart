import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/features/diagrams/voicings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('guitarVoicings maps names to dataset shapes', () async {
    await loadGuitarDb();

    // open chord, easiest position first
    expect(guitarVoicings('C').first.frets, [-1, 3, 2, 0, 1, 0]);
    // minor suffix
    expect(guitarVoicings('Am').first.frets, [-1, 0, 2, 2, 1, 0]);
    // barre chord carries its barre
    expect(guitarVoicings('F').first.barres, contains(1));
    // multiple positions available
    expect(guitarVoicings('C').length, greaterThan(1));
    // sharp/flat roots normalise to dataset keys
    expect(guitarVoicings('F#m'), isNotEmpty);
    expect(guitarVoicings('Bb'), isNotEmpty);
    // slash bass ignored → base shape still found
    expect(guitarVoicings('C/G').first.frets, guitarVoicings('C').first.frets);
    // unknown chord → empty (piano still renders)
    expect(guitarVoicings('Zx'), isEmpty);
  });

  test('pianoNotes returns triad for major and minor', () {
    expect(pianoNotes('C'), [0, 4, 7]); // C E G
    expect(pianoNotes('Am'), [9, 0, 4]); // A C E
  });
}
