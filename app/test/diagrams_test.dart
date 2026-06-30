// app/test/diagrams_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/features/diagrams/chord_diagram_sheet.dart';

Widget _wrap(Widget w) => MaterialApp(theme: chordMindLight, home: Scaffold(body: w));

void main() {
  testWidgets('ChordDiagramView shows chord name for a known chord', (t) async {
    await t.pumpWidget(_wrap(const ChordDiagramView(chord: 'C')));
    expect(find.text('C'), findsWidgets);
  });
  testWidgets('ChordDiagramView shows empty hint when chord is null', (t) async {
    await t.pumpWidget(_wrap(const ChordDiagramView(chord: null)));
    expect(find.textContaining('Chọn'), findsOneWidget);
  });
}
