import 'package:flutter/material.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/widgets/section_header.dart';
import 'grid_sync.dart';

class ChordGrid extends StatelessWidget {
  final AnalysisResult result;
  final double positionSeconds;
  final void Function(String chord)? onTapChord;
  const ChordGrid({super.key, required this.result, required this.positionSeconds, this.onTapChord});

  String? _segmentAt(double time) {
    for (final s in result.segments) {
      if (time >= s.start && time < s.end) return s.label;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    final active = activeChordIndex(result, positionSeconds);
    final perRow = result.source.timeSignature.clamp(2, 4);
    final cells = result.synchronizedChords;

    final children = <Widget>[];
    String? lastSeg;
    for (var i = 0; i < cells.length; i += perRow) {
      final rowStartTime = result.beats.isNotEmpty ? result.beats[cells[i].beatIndex].time : 0.0;
      final seg = _segmentAt(rowStartTime);
      if (seg != null && seg != lastSeg) {
        children.add(SectionHeader(title: seg));
        lastSeg = seg;
      }
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.s8),
        child: Row(children: [
          for (var j = i; j < i + perRow && j < cells.length; j++)
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
              child: _Cell(label: cells[j].chord, active: j == active, cm: cm,
                  onTap: () => onTapChord?.call(cells[j].chord)),
            )),
        ]),
      ));
    }
    return ListView(padding: const EdgeInsets.all(AppSpace.s16), children: children);
  }
}

class _Cell extends StatelessWidget {
  final String label;
  final bool active;
  final ChordMindColors cm;
  final VoidCallback onTap;
  const _Cell({required this.label, required this.active, required this.cm, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: active ? AppGradients.brand : null,
          color: active ? null : cm.chordIdle,
          borderRadius: BorderRadius.circular(AppRadii.md),
          boxShadow: active
              ? [BoxShadow(color: const Color(0xFFEC4899).withValues(alpha: 0.45), blurRadius: 18, spreadRadius: 1)]
              : null,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 20,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: active ? Colors.white : null)),
      ),
    );
  }
}
