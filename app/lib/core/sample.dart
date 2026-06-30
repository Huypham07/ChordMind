// app/lib/core/sample.dart
import 'models.dart';

/// Canned analysis for the /preview route and screenshots (no server needed).
final sampleAnalysis = AnalysisResult.fromJson({
  'songId': 'sample',
  'source': {'youtubeId': 'sample', 'title': 'Sample Song — Demo', 'duration': 16.0, 'bpm': 120.0, 'timeSignature': 4},
  'key': 'C major',
  'beats': [for (var i = 0; i < 32; i++) {'time': i * 0.5, 'beatNum': (i % 4) + 1}],
  'downbeats': [for (var i = 0; i < 8; i++) i * 2.0],
  'chords': [
    for (var i = 0; i < 8; i++)
      {'chord': ['C', 'G', 'Am', 'F'][i % 4], 'start': i * 2.0, 'end': i * 2.0 + 2.0, 'confidence': 0.95}
  ],
  'synchronizedChords': [
    for (var i = 0; i < 8; i++) {'chord': ['C', 'G', 'Am', 'F'][i % 4], 'beatIndex': i * 4}
  ],
  'segments': [
    {'label': 'verse', 'start': 0.0, 'end': 8.0},
    {'label': 'chorus', 'start': 8.0, 'end': 16.0},
  ],
});
