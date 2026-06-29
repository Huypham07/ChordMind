import 'package:flutter/material.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/theme.dart';
import 'grid_sync.dart';

class ChordGrid extends StatelessWidget {
  final AnalysisResult result;
  final double positionSeconds;
  final void Function(String chord)? onTapChord;
  const ChordGrid({super.key, required this.result, required this.positionSeconds, this.onTapChord});

  @override
  Widget build(BuildContext context) {
    final active = activeChordIndex(result, positionSeconds);
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, childAspectRatio: 1.4, mainAxisSpacing: 6, crossAxisSpacing: 6),
      itemCount: result.synchronizedChords.length,
      itemBuilder: (ctx, i) {
        final c = result.synchronizedChords[i];
        final on = i == active;
        return InkWell(
          onTap: () => onTapChord?.call(c.chord),
          child: Container(
            decoration: BoxDecoration(
              color: on ? cm.chordActive : cm.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(c.chord,
                style: TextStyle(fontSize: 18, fontWeight: on ? FontWeight.bold : FontWeight.normal)),
          ),
        );
      },
    );
  }
}
