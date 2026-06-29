import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';

void main() => runApp(const ProviderScope(child: ChordMindApp()));

class ChordMindApp extends StatelessWidget {
  const ChordMindApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ChordMind',
        theme: chordMindLight,
        darkTheme: chordMindDark,
        themeMode: ThemeMode.system,
        home: const Scaffold(body: Center(child: Text('ChordMind'))),
      );
}
