import 'package:flutter/material.dart';
import 'package:chordmind/core/theme.dart';

class PianoDiagram extends StatelessWidget {
  final List<int> notes; // semitone offsets 0..11
  const PianoDiagram(this.notes, {super.key});
  static const _whites = [0, 2, 4, 5, 7, 9, 11];
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return SizedBox(
      height: 90,
      child: Row(
        children: [
          for (final w in _whites)
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(1),
                color: notes.contains(w) ? cm.chordActive : Colors.white,
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}
