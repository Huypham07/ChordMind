import 'package:flutter/material.dart';

@immutable
class ChordMindColors extends ThemeExtension<ChordMindColors> {
  final Color chordActive;
  final Color beatMarker;
  final Color surfaceAlt;
  const ChordMindColors({
    required this.chordActive,
    required this.beatMarker,
    required this.surfaceAlt,
  });
  @override
  ChordMindColors copyWith({Color? chordActive, Color? beatMarker, Color? surfaceAlt}) =>
      ChordMindColors(
        chordActive: chordActive ?? this.chordActive,
        beatMarker: beatMarker ?? this.beatMarker,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      );
  @override
  ChordMindColors lerp(ChordMindColors? o, double t) => o ?? this;
}

// Fresh ChordMind identity: deep indigo + warm amber accent.
const _seed = Color(0xFF4F46E5);

ThemeData _build(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [
      ChordMindColors(
        chordActive: const Color(0xFFF59E0B),
        beatMarker: scheme.primary,
        surfaceAlt: scheme.surfaceContainerHighest,
      ),
    ],
  );
}

final chordMindLight = _build(Brightness.light);
final chordMindDark = _build(Brightness.dark);
