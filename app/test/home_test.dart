// app/test/home_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/features/home/home_screen.dart';
import 'package:chordmind/core/widgets/search_pill.dart';
import 'package:chordmind/core/widgets/gradient_button.dart';

void main() {
  testWidgets('home shows search pill and analyze button', (t) async {
    await t.binding.setSurfaceSize(const Size(1300, 900));
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(theme: chordMindLight, home: const HomeScreen())));
    expect(find.byType(SearchPill), findsOneWidget);
    expect(find.widgetWithText(GradientButton, 'Analyze'), findsOneWidget);
    await t.binding.setSurfaceSize(null);
  });
}
