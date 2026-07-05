import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chordmind/core/local_store.dart';

Map<String, dynamic> _analysis(String id, String title, {String? audioPath}) => {
      'songId': id, 'key': 'C major',
      'source': {
        'youtubeId': id, 'title': title, 'duration': 1.0, 'bpm': 120.0,
        'timeSignature': 4, if (audioPath != null) 'audioPath': audioPath,
      },
      'beats': [], 'downbeats': [], 'chords': [], 'synchronizedChords': [],
      'segments': [],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all() returns every stored song and skips corrupt entries', () async {
    SharedPreferences.setMockInitialValues({
      'song:v1:file:a.mp3': jsonEncode(_analysis('file:a.mp3', 'Song A', audioPath: '/s/a.mp3')),
      'song:v1:abcdefghijk': jsonEncode(_analysis('abcdefghijk', 'Song B')),
      'song:v1:corrupt': 'not json',
      'unrelated:key': 'ignored',
    });
    final all = await LocalStore().all();
    final byId = {for (final s in all) s.youtubeId: s};
    expect(byId.keys.toSet(), {'file:a.mp3', 'abcdefghijk'});
    expect(byId['file:a.mp3']!.title, 'Song A');
    expect(byId['file:a.mp3']!.audioPath, '/s/a.mp3');
    expect(byId['abcdefghijk']!.audioPath, isNull);
  });
}
