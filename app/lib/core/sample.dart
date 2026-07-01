// app/lib/core/sample.dart
import 'models.dart';

/// A placeholder analysis (fixed C–G–Am–F loop) for [youtubeId], used until the
/// real on-device analyzer lands. Returned as raw JSON so it can be persisted
/// as-is without per-model toJson.
/// ponytail: fake fixed loop; replace with the real analyzer (A1).
Map<String, dynamic> generateSampleJson(String youtubeId, {String? title}) => {
      'songId': youtubeId,
      'source': {
        'youtubeId': youtubeId,
        'title': title ?? 'Video YouTube',
        'duration': 16.0,
        'bpm': 120.0,
        'timeSignature': 4,
      },
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
    };

/// Canned analysis for the /preview route and screenshots (no server needed).
final sampleAnalysis = AnalysisResult.fromJson(generateSampleJson('sample', title: 'Sample Song — Demo'));
