// app/test/player_smoke_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/sample.dart';
import 'package:chordmind/core/song_repository.dart';
import 'package:chordmind/features/player/player_screen.dart';

class _FakeRepo implements SongRepository {
  @override
  Future<AnalysisResult> get(String id) async => sampleAnalysis;
  @override
  Future<AnalysisResult> submit(String url) async => sampleAnalysis;
  @override
  Future<List<({String youtubeId, String title})>> recent() async => [];
}

void main() {
  testWidgets('player loads analysis and shows Chords tab', (t) async {
    await t.binding.setSurfaceSize(const Size(1300, 900));
    await t.pumpWidget(ProviderScope(
      overrides: [songRepositoryProvider.overrideWithValue(_FakeRepo())],
      child: MaterialApp(theme: chordMindLight, home: const PlayerScreen('sample')),
    ));
    await t.pump(); // let the future resolve
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Chords'), findsOneWidget);
    await t.binding.setSurfaceSize(null);
  });
}
