// app/lib/core/on_device_analyzer.dart
//
// Plan B Task B1.5: assembles the on-device AnalysisResult JSON from the
// pieces built in B1.1-B1.4:
//   AudioSource.pcm -> PcmInferenceRunner.run -> voteDecode -> estimateKey
// and a synthetic beat grid (see below), then returns the raw JSON Map in
// the exact shape `AnalysisResult.fromJson` / `LocalStore.save` expect
// (mirrors `generateSampleJson`'s contract in sample.dart).
//
// Beat grid: NO beat model is exported yet (Plan A/C are chord-only; see
// the plan's Global Constraints). The chord grid
// (`features/chord_grid/chord_grid.dart`) renders from `beats` +
// `synchronizedChords`, so an empty beat list would hit its no-grid
// fallback. Until a real beat model (Beat-Transformer) lands, this emits a
// REGULAR SYNTHETIC grid at a placeholder 120 BPM / 4-4 time signature:
// one beat every 60/bpm seconds across the song's duration, beatNum
// cycling 1..4, downbeats where beatNum==1. This is NOT detected tempo —
// it is a fixed placeholder purely so the grid has something regular to
// snap chords to. Replace with real beat detection when that model ships.
import 'dart:typed_data';

import 'audio_source.dart';
import 'decode/key_krumhansl.dart';
import 'decode/vote_decode.dart';
import 'inference/pcm_runner.dart';
import 'model_registry.dart';
import 'models.dart';

/// Placeholder tempo used to synthesize a regular beat grid until a real
/// beat-tracking model is available on-device. See file header.
const placeholderBpm = 120.0;
const placeholderTimeSignature = 4;

class OnDeviceAnalyzer {
  OnDeviceAnalyzer({AudioSource? audioSource, this._registry})
      : audioSource = audioSource ?? AudioSource();

  final AudioSource audioSource;
  ModelRegistry? _registry;

  Future<ModelRegistry> _ensureRegistry() async => _registry ??= await ModelRegistry.load();

  /// Runs the full on-device analysis pipeline for [youtubeId] and returns
  /// the raw JSON Map matching `AnalysisResult.fromJson`'s expected shape.
  /// Throws on any pipeline failure (audio fetch/decode, ORT inference,
  /// etc.) — callers (e.g. `SongRepository.generate`) surface the error.
  Future<Map<String, dynamic>> analyze(String youtubeId, {String? title}) async {
    final Float32List pcm = await audioSource.pcm(youtubeId);
    final registry = await _ensureRegistry();
    final spec = registry.defaultModel;

    final runner = PcmInferenceRunner(spec);
    List<Chord> chords;
    try {
      final frames = await runner.run(pcm);
      chords = voteDecode(frames, spec);
    } finally {
      runner.dispose();
    }

    final key = estimateKey(chords);
    final duration = pcm.length / spec.fs;

    final interval = 60.0 / placeholderBpm;
    final beats = <Map<String, dynamic>>[];
    final downbeats = <double>[];
    var beatNum = 1;
    for (var t = 0.0; t < duration; t += interval) {
      beats.add({'time': t, 'beatNum': beatNum});
      if (beatNum == 1) downbeats.add(t);
      beatNum = beatNum % placeholderTimeSignature + 1;
    }

    String chordAt(double t) {
      if (chords.isEmpty) return 'N';
      for (final c in chords) {
        if (t >= c.start && t < c.end) return c.chord;
      }
      if (t < chords.first.start) return chords.first.chord;
      return chords.last.chord;
    }

    final synchronizedChords = [
      for (var i = 0; i < beats.length; i++)
        {'chord': chordAt(beats[i]['time'] as double), 'beatIndex': i},
    ];

    return {
      'songId': youtubeId,
      'source': {
        'youtubeId': youtubeId,
        'title': title ?? youtubeId,
        'duration': duration,
        'bpm': placeholderBpm,
        'timeSignature': placeholderTimeSignature,
      },
      'key': key,
      'beats': beats,
      'downbeats': downbeats,
      'chords': [
        for (final c in chords)
          {'chord': c.chord, 'start': c.start, 'end': c.end, 'confidence': c.confidence},
      ],
      'synchronizedChords': synchronizedChords,
      'segments': <Map<String, dynamic>>[],
      'melody': null,
    };
  }
}
