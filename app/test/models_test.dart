// app/test/models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/models.dart';

void main() {
  test('parses AnalysisResult from server JSON', () {
    final json = {
      'songId': 'abc',
      'source': {'youtubeId': 'abc', 'title': 'T', 'duration': 100.0, 'bpm': 120.0, 'timeSignature': 4},
      'key': 'C major',
      'beats': [{'time': 0.5, 'beatNum': 1}],
      'downbeats': [0.5],
      'chords': [{'chord': 'C', 'start': 0.5, 'end': 2.0, 'confidence': 0.9}],
      'synchronizedChords': [{'chord': 'C', 'beatIndex': 0}],
      'segments': [{'label': 'verse', 'start': 0.0, 'end': 100.0}],
      'melody': null,
    };
    final r = AnalysisResult.fromJson(json);
    expect(r.source.youtubeId, 'abc');
    expect(r.synchronizedChords.first.chord, 'C');
    expect(r.beats.length, 1);
  });
}
