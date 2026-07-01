// app/test/chord_grid_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/sample.dart';
import 'package:chordmind/features/chord_grid/current_chord_bar.dart';
import 'package:chordmind/features/chord_grid/chord_grid.dart';

Widget _wrap(Widget w) => MaterialApp(theme: chordMindLight, home: Scaffold(body: w));

void main() {
  testWidgets('CurrentChordBar shows the active chord at a position', (t) async {
    await t.pumpWidget(_wrap(CurrentChordBar(result: sampleAnalysis, positionSeconds: 0.5)));
    expect(find.text('C'), findsWidgets); // C is active at t=0.5
  });

  testWidgets('ChordGrid renders all cells and a section header', (t) async {
    await t.binding.setSurfaceSize(const Size(900, 1400));
    await t.pumpWidget(_wrap(ChordGrid(result: sampleAnalysis, positionSeconds: 0.0)));
    expect(find.text('VERSE'), findsOneWidget); // SectionHeader uppercases
    await t.binding.setSurfaceSize(null);
  });
}
