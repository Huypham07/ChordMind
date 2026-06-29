import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';

void main() {
  test('themes expose ChordMind semantic colors', () {
    final c = chordMindLight.extension<ChordMindColors>();
    expect(c, isNotNull);
    expect(chordMindDark.extension<ChordMindColors>(), isNotNull);
    expect(c!.chordActive, isNot(c.beatMarker));
  });
}
