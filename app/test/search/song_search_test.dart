import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chordmind/core/local_store.dart';
import 'package:chordmind/core/search/song_search.dart';

Map<String, dynamic> _a(String id, String title) => {
      'songId': id, 'key': 'C major',
      'source': {'youtubeId': id, 'title': title, 'duration': 1.0, 'bpm': 120.0, 'timeSignature': 4},
      'beats': [], 'downbeats': [], 'chords': [], 'synchronizedChords': [], 'segments': [],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'song:v1:one': jsonEncode(_a('one', 'Hotel California')),
      'song:v1:two': jsonEncode(_a('two', 'california dreamin')),
      'song:v1:three': jsonEncode(_a('three', 'Yesterday')),
    });
  });

  DefaultSongSearch _search({Future<List<YtResult>> Function(String)? yt}) =>
      DefaultSongSearch(LocalStore(), youtubeSearcher: yt ?? (_) async => []);

  test('searchLocal matches title (case-insensitive, contains)', () async {
    final r = await _search().searchLocal('CALI');
    expect(r.map((s) => s.title).toSet(), {'Hotel California', 'california dreamin'});
  });

  test('searchLocal on empty/whitespace query returns nothing', () async {
    expect(await _search().searchLocal('   '), isEmpty);
  });

  test('searchYoutube delegates to the injected searcher', () async {
    final r = await _search(
      yt: (q) async => [YtResult('vid1', 'Result for $q', 'Chan', null)],
    ).searchYoutube('abba');
    expect(r.single.videoId, 'vid1');
    expect(r.single.title, 'Result for abba');
  });

  test('searchYoutube on empty query short-circuits (no searcher call)', () async {
    var called = false;
    final r = await _search(yt: (_) async { called = true; return []; }).searchYoutube('  ');
    expect(r, isEmpty);
    expect(called, isFalse);
  });
}
