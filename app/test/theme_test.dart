// app/test/theme_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:chordmind/core/theme.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    // Pre-warm the lazy theme globals so that async font-load futures
    // (which rethrow in google_fonts 8.x) fire here and are suppressed,
    // not in the test body zone where they would fail the test.
    await runZonedGuarded(
      () async {
        // ignore: unnecessary_statements — triggers lazy initialisation
        chordMindLight;
        chordMindDark;
        // Yield so pending font futures fire within this zone.
        await Future<void>.delayed(Duration.zero);
      },
      (e, _) {
        // Swallow google_fonts font-not-found errors; surface anything else.
        if (!e.toString().contains('GoogleFonts') &&
            !e.toString().contains('google_fonts') &&
            !e.toString().contains('allowRuntimeFetching')) {
          // ignore: only_throw_errors
          throw e;
        }
      },
    );
  });

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
}
