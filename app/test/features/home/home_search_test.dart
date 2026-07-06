import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/features/home/home_screen.dart';

Map<String, dynamic> _a(String id, String title) => {
      'songId': id, 'key': 'C major',
      'source': {'youtubeId': id, 'title': title, 'duration': 1.0, 'bpm': 120.0, 'timeSignature': 4},
      'beats': [], 'downbeats': [], 'chords': [], 'synchronizedChords': [], 'segments': [],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typing a title shows the matching local song', (t) async {
    SharedPreferences.setMockInitialValues({
      'song:v1:one': jsonEncode(_a('one', 'Hotel California')),
    });
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/player/:id', builder: (_, __) => const Scaffold()),
    ]);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(theme: chordMindLight, routerConfig: router),
    ));
    await t.pump(); // let the first frame build

    await t.enterText(find.byType(TextField).first, 'hotel');
    // Debounce + async search; advance time and pump frames without settling.
    await t.pump(const Duration(milliseconds: 350));
    await t.pump();

    expect(find.text('Hotel California'), findsOneWidget);
    expect(find.text('Đã có hợp âm'), findsWidgets);
  });
}
