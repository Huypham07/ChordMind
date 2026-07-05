// app/lib/core/on_device_analyzer.dart
//
// Plan B Task B1.5 (+ beat-sync follow-up): assembles the on-device
// AnalysisResult JSON from the pieces built in B1.1-B1.4 plus the DSP beat
// tracker:
//   AudioSource.pcm -> PcmInferenceRunner.run -> DspBeatTracker.track
//   -> beatSyncChords (or voteDecode fallback) -> estimateKey
// then returns the raw JSON Map in the exact shape
// `AnalysisResult.fromJson` / `LocalStore.save` expect (mirrors
// `generateSampleJson`'s contract in sample.dart).
//
// Beat grid: `DspBeatTracker` estimates real beat times + tempo from the
// PCM (spectral-flux onset -> autocorrelation tempo -> Ellis DP beat
// tracking). When it finds beats, chords are decoded beat-synchronously
// (`beatSyncChords`) and `beats[]`/`source.bpm` reflect the real estimate,
// with `beatNum` still cycling 1..4 (no downbeat/time-signature model
// yet). If the tracker throws or returns no beats, this falls back to the
// old REGULAR SYNTHETIC grid at a placeholder 120 BPM / 4-4 time
// signature (one beat every 60/bpm seconds across the song's duration)
// and frame-level `voteDecode`, so the chord grid
// (`features/chord_grid/chord_grid.dart`) always has something to snap
// chords to.
import 'package:flutter/foundation.dart';

import 'audio_source.dart';
import 'beat/beat_tracker.dart';
import 'decode/beat_sync.dart';
import 'decode/key_krumhansl.dart';
import 'decode/vote_decode.dart';
import 'inference/pcm_runner.dart';
import 'model_registry.dart';
import 'models.dart';

/// Placeholder tempo used to synthesize a regular beat grid until a real
/// beat-tracking model is available on-device. See file header.
const placeholderBpm = 120.0;
const placeholderTimeSignature = 4;

/// Beat-sync chords shorter than this many beats are absorbed into a stronger
/// neighbor, so a lone 1-beat quality flip (e.g. Cmaj7 wedged between C beats)
/// vanishes while real >=2-beat changes survive. Tempo-scaled via the beat
/// grid, so it means the same musically at any BPM.
/// ponytail: one calibration knob — lower it to keep more short chords, raise
/// it to be more aggressive against flicker.
const minChordBeats = 1.4;

/// Median spacing (seconds) between consecutive [beatTimes]; 0 if under 2 beats.
double _medianBeatSpacing(List<double> beatTimes) {
  if (beatTimes.length < 2) return 0;
  final d = [for (var i = 1; i < beatTimes.length; i++) beatTimes[i] - beatTimes[i - 1]]
    ..sort();
  return d[d.length ~/ 2];
}

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
  ///
  /// [modelName] selects which chord model (see `ModelRegistry`) to run;
  /// `null` (the default) resolves to the registry's default model
  /// (btc). Callers pass the user's `settings_store.dart`
  /// selection here.
  /// [audioFilePath], when given, decodes that LOCAL audio file instead of
  /// fetching from YouTube (fallback for rate-limiting / non-YouTube audio).
  Future<Map<String, dynamic>> analyze(String youtubeId,
      {String? title, String? modelName, String? audioFilePath}) async {
    debugPrint('[analyze] start id=$youtubeId model=${modelName ?? "(default)"}'
        '${audioFilePath != null ? " file=$audioFilePath" : ""}');
    final Float32List pcm = audioFilePath != null
        ? await audioSource.pcmFromFile(audioFilePath)
        : await audioSource.pcm(youtubeId);
    debugPrint('[analyze] pcm ready: ${pcm.length} samples');
    final registry = await _ensureRegistry();
    final spec = registry.byName(modelName);
    debugPrint('[analyze] model=${spec.name} input=${spec.input}');

    final runner = PcmInferenceRunner(spec);
    List<Chord> chords;
    BeatResult beatResult;
    try {
      final frames = await runner.run(pcm);
      debugPrint('[analyze] inference done: ${frames.length} frames');
      try {
        beatResult = const DspBeatTracker().track(pcm, sr: spec.fs.toDouble());
      } catch (e) {
        debugPrint('[analyze] beat tracking failed: $e — falling back');
        beatResult = const BeatResult([], 0);
      }
      final beatTimes = beatResult.beats;
      final minChordDur = minChordBeats * _medianBeatSpacing(beatTimes);
      chords = beatTimes.isEmpty
          ? voteDecode(frames, spec)
          : beatSyncChords(frames, beatTimes, spec, minChordDur: minChordDur);
      // Diagnostics: bpm + beat/chord counts + the chord sequence let us tell
      // real over-segmentation from a doubled-tempo beat grid.
      debugPrint('[analyze] bpm=${beatResult.bpm.toStringAsFixed(1)} '
          '${beatTimes.length} beats, ${chords.length} chords');
      debugPrint('[analyze] chords: ${chords.map((c) => c.chord).join(' ')}');
    } finally {
      runner.dispose();
    }
    debugPrint('[analyze] decoded ${chords.length} chords');

    final key = estimateKey(chords);
    debugPrint('[analyze] key=$key — done');
    final duration = pcm.length / spec.fs;

    final beatTimes = beatResult.beats;
    final bpm = beatTimes.isEmpty ? placeholderBpm : beatResult.bpm;
    final beats = <Map<String, dynamic>>[];
    final downbeats = <double>[];
    if (beatTimes.isEmpty) {
      // Fallback: no real beats — emit the placeholder grid as before.
      final interval = 60.0 / placeholderBpm;
      var beatNum = 1;
      for (var t = 0.0; t < duration; t += interval) {
        beats.add({'time': t, 'beatNum': beatNum});
        if (beatNum == 1) downbeats.add(t);
        beatNum = beatNum % placeholderTimeSignature + 1;
      }
    } else {
      // Real beats; beatNum cycles as a placeholder meter (no downbeat model).
      for (var i = 0; i < beatTimes.length; i++) {
        final beatNum = i % placeholderTimeSignature + 1;
        beats.add({'time': beatTimes[i], 'beatNum': beatNum});
        if (beatNum == 1) downbeats.add(beatTimes[i]);
      }
    }

    String chordAt(double t) {
      if (chords.isEmpty) return 'N';
      for (final c in chords) {
        if (t >= c.start && t < c.end) return c.chord;
      }
      if (t < chords.first.start) return chords.first.chord;
      return chords.last.chord;
    }

    // Emit a synchronizedChord only where the chord CHANGES (not once per beat),
    // so the grid shows a label at the start of each run and blanks between —
    // e.g. one "G" at the start of a G phrase, not G on every beat.
    final synchronizedChords = <Map<String, dynamic>>[];
    String? prevChord;
    for (var i = 0; i < beats.length; i++) {
      final ch = chordAt(beats[i]['time'] as double);
      if (ch != prevChord) {
        synchronizedChords.add({'chord': ch, 'beatIndex': i});
        prevChord = ch;
      }
    }

    return {
      'songId': youtubeId,
      'source': {
        'youtubeId': youtubeId,
        'title': title ?? youtubeId,
        'duration': duration,
        'bpm': bpm,
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
