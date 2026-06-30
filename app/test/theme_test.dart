// app/test/theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';

void main() {
  test('themes expose vibrant ChordMind tokens for light and dark', () {
    for (final t in [chordMindLight, chordMindDark]) {
      final c = t.extension<ChordMindColors>();
      expect(c, isNotNull);
      expect(c!.chordActive, isNot(c.chordIdle));
      expect(c.textMuted, isNot(c.border));
    }
    expect(AppGradients.brand.colors.first, const Color(0xFF8B5CF6));
    expect(AppGradients.brand.colors.last, const Color(0xFFEC4899));
    expect(AppRadii.lg, 16.0);
  });

  test('text theme uses the bundled Google Sans family', () {
    expect(chordMindLight.textTheme.titleLarge?.fontFamily, 'Google Sans');
    expect(chordMindLight.textTheme.bodyMedium?.fontFamily, 'Google Sans');
  });
}
