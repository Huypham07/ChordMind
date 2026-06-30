// app/lib/core/theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppRadii {
  static const sm = 8.0, md = 12.0, lg = 16.0, xl = 20.0, pill = 999.0;
}

class AppSpace {
  static const s4 = 4.0, s8 = 8.0, s12 = 12.0, s16 = 16.0, s24 = 24.0, s32 = 32.0, s48 = 48.0;
}

class AppGradients {
  static const brand = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppShadows {
  static List<BoxShadow> soft(Brightness b) => [
        BoxShadow(
          color: b == Brightness.dark
              ? Colors.black.withValues(alpha: 0.40)
              : const Color(0xFF141020).withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];
}

@immutable
class ChordMindColors extends ThemeExtension<ChordMindColors> {
  final Color chordActive, chordIdle, beatMarker, surfaceAlt, textMuted, border;
  final Color segmentVerse, segmentChorus, segmentOther, danger;
  const ChordMindColors({
    required this.chordActive,
    required this.chordIdle,
    required this.beatMarker,
    required this.surfaceAlt,
    required this.textMuted,
    required this.border,
    required this.segmentVerse,
    required this.segmentChorus,
    required this.segmentOther,
    required this.danger,
  });
  @override
  ChordMindColors copyWith({
    Color? chordActive, Color? chordIdle, Color? beatMarker, Color? surfaceAlt,
    Color? textMuted, Color? border, Color? segmentVerse, Color? segmentChorus,
    Color? segmentOther, Color? danger,
  }) =>
      ChordMindColors(
        chordActive: chordActive ?? this.chordActive,
        chordIdle: chordIdle ?? this.chordIdle,
        beatMarker: beatMarker ?? this.beatMarker,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        textMuted: textMuted ?? this.textMuted,
        border: border ?? this.border,
        segmentVerse: segmentVerse ?? this.segmentVerse,
        segmentChorus: segmentChorus ?? this.segmentChorus,
        segmentOther: segmentOther ?? this.segmentOther,
        danger: danger ?? this.danger,
      );
  @override
  ChordMindColors lerp(ChordMindColors? o, double t) {
    if (o == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ChordMindColors(
      chordActive: l(chordActive, o.chordActive),
      chordIdle: l(chordIdle, o.chordIdle),
      beatMarker: l(beatMarker, o.beatMarker),
      surfaceAlt: l(surfaceAlt, o.surfaceAlt),
      textMuted: l(textMuted, o.textMuted),
      border: l(border, o.border),
      segmentVerse: l(segmentVerse, o.segmentVerse),
      segmentChorus: l(segmentChorus, o.segmentChorus),
      segmentOther: l(segmentOther, o.segmentOther),
      danger: l(danger, o.danger),
    );
  }
}

const _primary = Color(0xFF8B5CF6);
const _secondary = Color(0xFFEC4899);

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _primary,
    brightness: b,
    primary: _primary,
    secondary: _secondary,
    surface: dark ? const Color(0xFF1A1820) : Colors.white,
  ).copyWith(
    surface: dark ? const Color(0xFF1A1820) : Colors.white,
  );
  final bg = dark ? const Color(0xFF0E0D12) : const Color(0xFFFAFAFB);
  final text = dark ? const Color(0xFFECEAF2) : const Color(0xFF1A1820);

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: bg);
  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displaySmall: GoogleFonts.sora(fontSize: 28, fontWeight: FontWeight.w700, color: text),
      headlineSmall: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w700, color: text),
      titleLarge: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w600, color: text),
      titleMedium: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w600, color: text),
    ),
    extensions: [
      ChordMindColors(
        chordActive: _primary, // gradient drawn at widget level; this is the fallback solid
        chordIdle: dark ? const Color(0xFF232030) : const Color(0xFFF2F1F5),
        beatMarker: _primary,
        surfaceAlt: dark ? const Color(0xFF232030) : const Color(0xFFF2F1F5),
        textMuted: dark ? const Color(0xFF9D98AD) : const Color(0xFF6B6878),
        border: dark ? const Color(0xFF2A2733) : const Color(0xFFE6E4EC),
        segmentVerse: _primary.withValues(alpha: 0.14),
        segmentChorus: _secondary.withValues(alpha: 0.14),
        segmentOther: (dark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        danger: const Color(0xFFF43F5E),
      ),
    ],
  );
}

final chordMindLight = _theme(Brightness.light);
final chordMindDark = _theme(Brightness.dark);
