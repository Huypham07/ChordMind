import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/search/song_search.dart';
import 'package:chordmind/features/home/home_screen.dart';

Map<String, dynamic> _a(String id, String title) => {
      'songId': id, 'key': 'C major',
      'source': {'youtubeId': id, 'title': title, 'duration': 1.0, 'bpm': 120.0, 'timeSignature': 4},
      'beats': [], 'downbeats': [], 'chords': [], 'synchronizedChords': [], 'segments': [],
    };

/// A [SongSearch] whose YouTube search always fails, to exercise the
/// error path (no stuck spinner, error surfaced).
class _FailingYtSearch implements SongSearch {
  @override
  Future<List<StoredSong>> searchLocal(String query) async => [];

  @override
  Future<List<YtResult>> searchYoutube(String query) async {
    throw Exception('network unreachable');
  }
}

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

  testWidgets('YouTube search failure clears the spinner and shows an error', (t) async {
    SharedPreferences.setMockInitialValues({});
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/player/:id', builder: (_, __) => const Scaffold()),
    ]);
    await t.pumpWidget(ProviderScope(
      overrides: [songSearchProvider.overrideWithValue(_FailingYtSearch())],
      child: MaterialApp.router(theme: chordMindLight, routerConfig: router),
    ));
    await t.pump(); // let the first frame build

    await t.enterText(find.byType(TextField).first, 'no such song');
    await t.pump(const Duration(milliseconds: 350)); // debounce fires local search
    await t.pump();

    await t.tap(find.text('Tìm trên YouTube'));
    await t.pump(); // let the rejected future settle and the frame rebuild

    expect(find.text('Đang tìm…'), findsNothing);
    expect(find.text('Tìm trên YouTube'), findsOneWidget);
    expect(find.text('Không tìm được trên YouTube'), findsOneWidget);
  });
}
