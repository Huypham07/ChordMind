// app/test/widgets_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/widgets/gradient_button.dart';
import 'package:chordmind/core/widgets/pill_tabs.dart';

Widget _wrap(Widget w) => MaterialApp(theme: chordMindLight, home: Scaffold(body: w));

void main() {
  testWidgets('GradientButton shows label and fires onPressed', (t) async {
    var tapped = false;
    await t.pumpWidget(_wrap(GradientButton(label: 'Analyze', onPressed: () => tapped = true)));
    expect(find.text('Analyze'), findsOneWidget);
    await t.tap(find.text('Analyze'));
    expect(tapped, isTrue);
  });

  testWidgets('PillTabs reports tapped index', (t) async {
    var idx = 0;
    await t.pumpWidget(_wrap(StatefulBuilder(
      builder: (_, set) => PillTabs(
        tabs: const ['Chords', 'Lyrics'], index: idx,
        onChanged: (i) => set(() => idx = i)),
    )));
    await t.tap(find.text('Lyrics'));
    await t.pump();
    expect(idx, 1);
  });
}
