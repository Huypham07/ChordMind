import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/transpose.dart';

void main() {
  test('transposeChord', () {
    expect(transposeChord('C', 2), 'D');
    expect(transposeChord('B', 1), 'C'); // wraps
    expect(transposeChord('Am', 3), 'Cm'); // keeps suffix
    expect(transposeChord('F#m7', 1), 'Gm7'); // sharp root + suffix
    expect(transposeChord('C/E', 2), 'D/F#'); // slash bass
    expect(transposeChord('C', -1), 'B'); // negative wraps
    expect(transposeChord('G', 0), 'G'); // no-op
    expect(transposeChord('Bb', 2), 'C'); // flat root normalised to sharps
  });
}
