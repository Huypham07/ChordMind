import 'package:flutter/material.dart';
import 'package:chordmind/core/theme.dart';

class PianoDiagram extends StatelessWidget {
  final List<int> notes; // semitone offsets 0..11
  const PianoDiagram(this.notes, {super.key});
  static const _white = [0, 2, 4, 5, 7, 9, 11];
  static const _blackAfter = {0: 1, 1: 3, 3: 6, 4: 8, 5: 10}; // white index -> black semitone

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 110, child: LayoutBuilder(builder: (context, c) {
      final ww = c.maxWidth / 7;
      return Stack(children: [
        Row(children: [
          for (final w in _white)
            Expanded(child: Container(
              height: 110,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                gradient: notes.contains(w) ? AppGradients.brand : null,
                color: notes.contains(w) ? null : Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
                border: Border.all(color: Colors.black26),
              ),
            )),
        ]),
        for (final e in _blackAfter.entries)
          Positioned(
            left: (e.key + 1) * ww - ww * 0.3,
            child: Container(
              width: ww * 0.6, height: 68,
              decoration: BoxDecoration(
                gradient: notes.contains(e.value) ? AppGradients.brand : null,
                color: notes.contains(e.value) ? null : Colors.black,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
              ),
            ),
          ),
      ]);
    }));
  }
}
