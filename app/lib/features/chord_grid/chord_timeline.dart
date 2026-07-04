// app/lib/features/chord_grid/chord_timeline.dart
import 'package:flutter/material.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/transpose.dart';

/// Time-based chord view. Renders the model's REAL chord segments (their actual
/// start/end times) and highlights the one currently playing based on
/// [positionSeconds]. There is no synthetic beat/measure grid — the highlight
/// follows real playback time, so chords stay in sync with the audio regardless
/// of tempo or meter (which we don't detect yet). N/no-chord segments are
/// skipped so only real chords show.
class ChordTimeline extends StatelessWidget {
  final AnalysisResult result;
  final double positionSeconds;
  final int semitones;
  final String songKey;
  final void Function(String)? onTapChord;

  const ChordTimeline({
    super.key,
    required this.result,
    required this.positionSeconds,
    this.semitones = 0,
    this.songKey = 'C major',
    this.onTapChord,
  });

  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    final segs = <({String label, double start, double end})>[];
    for (final c in result.chords) {
      final lbl = shortChord(transposeChord(c.chord, semitones, key: songKey));
      if (lbl.isNotEmpty) segs.add((label: lbl, start: c.start, end: c.end)); // skip N/X
    }
    if (segs.isEmpty) {
      return Center(child: Text('Chưa có hợp âm', style: TextStyle(color: cm.textMuted)));
    }
    final active =
        segs.indexWhere((s) => positionSeconds >= s.start && positionSeconds < s.end);

    return SingleChildScrollView(
      child: Wrap(
        spacing: AppSpace.s8,
        runSpacing: AppSpace.s8,
        children: [
          for (var i = 0; i < segs.length; i++)
            _ChordPill(
              label: segs[i].label,
              active: i == active,
              cm: cm,
              onTap: onTapChord == null ? null : () => onTapChord!(segs[i].label),
            ),
        ],
      ),
    );
  }
}

class _ChordPill extends StatelessWidget {
  final String label;
  final bool active;
  final ChordMindColors cm;
  final VoidCallback? onTap;
  const _ChordPill({required this.label, required this.active, required this.cm, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s12),
        decoration: BoxDecoration(
          gradient: active ? AppGradients.brand : null,
          color: active ? null : cm.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: active ? null : Border.all(color: cm.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : null,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
