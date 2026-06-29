// app/test/home_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/features/home/home_screen.dart';

void main() {
  testWidgets('home shows url field and analyze button', (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: HomeScreen())));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Analyze'), findsOneWidget);
  });
}
