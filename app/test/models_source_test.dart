// app/test/models_source_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/models.dart';

Map<String, dynamic> _src({String? audioPath}) => {
      'youtubeId': 'file:a.mp3', 'title': 'A', 'duration': 1.0, 'bpm': 120.0,
      'timeSignature': 4, if (audioPath != null) 'audioPath': audioPath,
    };

void main() {
  test('Source.audioPath round-trips and defaults to null when absent', () {
    expect(Source.fromJson(_src()).audioPath, isNull);
    expect(Source.fromJson(_src(audioPath: '/x/songs/a.mp3')).audioPath,
        '/x/songs/a.mp3');
  });
}
