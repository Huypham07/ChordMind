// app/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/theme_mode.dart';
import 'core/router.dart';

void main() => runApp(const ProviderScope(child: ChordMindApp()));

class ChordMindApp extends ConsumerWidget {
  const ChordMindApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'ChordMind',
        debugShowCheckedModeBanner: false,
        theme: chordMindLight,
        darkTheme: chordMindDark,
        themeMode: ref.watch(themeModeProvider),
        themeAnimationDuration: Duration.zero,
        routerConfig: router,
      );
}
