import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/features/player/effective_audio_path.dart';

AnalysisResult _r({String? audioPath}) => AnalysisResult.fromJson({
      'songId': 'file:a.mp3', 'key': 'C major',
      'source': {
        'youtubeId': 'file:a.mp3', 'title': 'A', 'duration': 1.0, 'bpm': 120.0,
        'timeSignature': 4, if (audioPath != null) 'audioPath': audioPath,
      },
      'beats': [], 'downbeats': [], 'chords': [], 'synchronizedChords': [], 'segments': [],
    });

void main() {
  test('prefers the router-provided path when present', () {
    expect(effectiveAudioPath('/picked/x.mp3', _r(audioPath: '/persisted/x.mp3')), '/picked/x.mp3');
  });
  test('falls back to the result audioPath when no router path', () {
    expect(effectiveAudioPath(null, _r(audioPath: '/persisted/x.mp3')), '/persisted/x.mp3');
  });
  test('null when neither is available', () {
    expect(effectiveAudioPath(null, _r()), isNull);
    expect(effectiveAudioPath(null, null), isNull);
  });
}
