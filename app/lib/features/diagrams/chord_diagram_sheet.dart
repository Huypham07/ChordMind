import 'package:flutter/material.dart';
import 'voicings.dart';
import 'guitar_diagram.dart';
import 'piano_diagram.dart';

void showChordDiagram(BuildContext context, String chord) {
  showModalBottomSheet(
    context: context,
    builder: (_) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(chord, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        if (guitarVoicings[chord] != null) GuitarDiagram(guitarVoicings[chord]!),
        const SizedBox(height: 12),
        PianoDiagram(pianoNotes(chord)),
      ]),
    ),
  );
}
