import 'package:flutter/material.dart';
import 'package:chordmind/core/theme.dart';
import 'voicings.dart';
import 'guitar_diagram.dart';
import 'piano_diagram.dart';

class ChordDiagramView extends StatelessWidget {
  final String? chord;
  const ChordDiagramView({super.key, this.chord});
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    if (chord == null) {
      return Center(child: Text('Chọn một hợp âm để xem thế bấm',
          style: TextStyle(color: cm.textMuted)));
    }
    final v = guitarVoicings[chord];
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(chord!, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpace.s24),
        if (v != null) GuitarDiagram(v, name: chord),
        const SizedBox(height: AppSpace.s24),
        PianoDiagram(pianoNotes(chord!)),
      ]),
    );
  }
}

void showChordDiagram(BuildContext context, String chord) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => ChordDiagramView(chord: chord),
  );
}
