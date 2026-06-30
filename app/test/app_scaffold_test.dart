// app/test/app_scaffold_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/breakpoints.dart';
import 'package:chordmind/core/widgets/app_scaffold.dart';

void main() {
  test('formFactorFor maps widths', () {
    expect(formFactorFor(500), FormFactor.compact);
    expect(formFactorFor(800), FormFactor.medium);
    expect(formFactorFor(1300), FormFactor.expanded);
  });

  testWidgets('expanded shows NavigationRail, compact shows NavigationBar', (t) async {
    await t.binding.setSurfaceSize(const Size(1300, 900));
    await t.pumpWidget(MaterialApp(theme: chordMindLight,
      home: const AppScaffold(title: 'X', body: SizedBox())));
    expect(find.byType(NavigationRail), findsOneWidget);

    await t.binding.setSurfaceSize(const Size(420, 900));
    await t.pumpWidget(MaterialApp(theme: chordMindLight,
      home: const AppScaffold(title: 'X', body: SizedBox())));
    expect(find.byType(NavigationBar), findsOneWidget);
    await t.binding.setSurfaceSize(null);
  });
}
