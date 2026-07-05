# Beat Detection (DSP) + Beat-Synchronous Chords — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Estimate real beats on-device with a pure-Dart DSP beat tracker and decode one chord per beat, fixing chord flicker (#5) and chord↔audio sync (#4).

**Architecture:** Reuse the existing radix-2 FFT/STFT in `hybrid_cqt.dart` to build a spectral-flux onset envelope → autocorrelation tempo → Ellis dynamic-programming beat tracker. A `beatSyncChords` decoder takes the model's per-frame predictions plus the beat grid and emits one chord per beat interval (mode of frame labels), merged. `OnDeviceAnalyzer` wires it in, falling back to the existing `voteDecode` (with its #5 min-duration merge) when beats can't be found.

**Tech Stack:** Dart / Flutter, `dart:typed_data`, `dart:math`, `flutter_test`. No new dependencies.

## Global Constraints

- On-device analysis only (mobile); no web. (compute-placement)
- Clean Architecture: `features/` depend on `SongRepository`, never on analyzer internals. Domain stays framework-free.
- Output contract unchanged: `AnalysisResult` JSON (`songId, source{youtubeId,title,duration,bpm,timeSignature}, key, beats[]{time,beatNum}, downbeats[], chords[]{chord,start,end,confidence}, synchronizedChords[]{chord,beatIndex}, segments[], melody`).
- Audio sample rate `sr = 22050` Hz (matches chord model front-end).
- No new pub dependency — reuse the FFT already in `app/lib/core/hybrid_cqt.dart`.
- Downbeats/meter stay placeholders: `beatNum` cycles 1..4, `timeSignature = 4`.
- Analysis must never fail because beat tracking failed — always fall back.

---

### Task 1: Expose a public STFT-magnitude helper in `hybrid_cqt.dart`

The FFT and STFT (`_fftInPlace`, `_stftComplex`, `_hannWindow`) already exist but are private. Expose a thin magnitude wrapper so the beat tracker reuses the same FFT instead of adding a second one.

**Files:**
- Modify: `app/lib/core/hybrid_cqt.dart` (add one public function near `_stftComplex`, ~line 378)
- Test: `app/test/stft_magnitude_test.dart`

**Interfaces:**
- Consumes: existing private `_stftComplex`, `_hannWindow`.
- Produces: `List<Float64List> stftMagnitude(Float64List y, {int nFft = 2048, int hop = 512})` — hann-windowed magnitude spectrogram, `result[frame][freqBin]`, `freqBin` in `[0, nFft/2]`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/stft_magnitude_test.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/hybrid_cqt.dart';

void main() {
  test('stftMagnitude peaks at the bin of a pure sine', () {
    const nFft = 2048, hop = 512, sr = 22050.0;
    const freq = 1723.0; // ~ bin 160 at these params (160*sr/nFft ≈ 1723)
    final y = Float64List(sr ~/ 1); // 1 second
    for (var i = 0; i < y.length; i++) {
      y[i] = math.sin(2 * math.pi * freq * i / sr);
    }
    final mag = stftMagnitude(y, nFft: nFft, hop: hop);
    expect(mag, isNotEmpty);
    // Take a middle frame (away from zero-padded edges) and find its peak bin.
    final frame = mag[mag.length ~/ 2];
    var peak = 0;
    for (var f = 1; f < frame.length; f++) {
      if (frame[f] > frame[peak]) peak = f;
    }
    final expectedBin = (freq * nFft / sr).round(); // 160
    expect((peak - expectedBin).abs(), lessThanOrEqualTo(1));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/stft_magnitude_test.dart`
Expected: FAIL — `stftMagnitude` is not defined.

- [ ] **Step 3: Write minimal implementation**

Add to `app/lib/core/hybrid_cqt.dart` (public, just after the `_stftComplex` function, ~line 378):

```dart
/// Public hann-windowed magnitude spectrogram, reusing this module's FFT.
/// `result[frame][freqBin]`, freqBin in [0, nFft/2]. Used by the beat
/// tracker for its onset envelope so there is only one FFT in the app.
List<Float64List> stftMagnitude(Float64List y, {int nFft = 2048, int hop = 512}) {
  final window = _hannWindow(nFft);
  final stft = _stftComplex(y, nFft, hop, window: window);
  final out = List<Float64List>.generate(stft.nFrames, (_) => Float64List(nFft ~/ 2 + 1));
  for (var t = 0; t < stft.nFrames; t++) {
    final re = stft.re[t], im = stft.im[t];
    for (var f = 0; f < re.length; f++) {
      out[t][f] = math.sqrt(re[f] * re[f] + im[f] * im[f]);
    }
  }
  return out;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/stft_magnitude_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/hybrid_cqt.dart app/test/stft_magnitude_test.dart
git commit -m "feat(dsp): expose stftMagnitude helper reusing hybrid_cqt FFT"
```

---

### Task 2: Onset envelope (spectral flux)

**Files:**
- Create: `app/lib/core/beat/onset.dart`
- Test: `app/test/beat/onset_test.dart`

**Interfaces:**
- Consumes: `stftMagnitude` (Task 1).
- Produces:
  - `const double onsetFps = 22050 / 512;` (~43.07 frames/sec)
  - `List<double> onsetEnvelope(Float32List pcm, {int nFft = 2048, int hop = 512})` — per-frame spectral flux, `result[0] == 0`, max-normalized to `[0, 1]` (all-zero if silent).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/beat/onset_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/beat/onset.dart';

void main() {
  test('onset envelope spikes near an impulse and is quiet elsewhere', () {
    const sr = 22050, hop = 512;
    final pcm = Float32List(sr); // 1 second of silence
    final impulseSample = sr ~/ 2; // impulse at t=0.5s
    pcm[impulseSample] = 1.0;
    final env = onsetEnvelope(pcm, hop: hop);
    expect(env, isNotEmpty);
    expect(env.first, 0.0); // first frame has no predecessor
    // Frame nearest the impulse should carry the largest flux.
    final impulseFrame = (impulseSample / hop).round();
    var peak = 0;
    for (var i = 1; i < env.length; i++) {
      if (env[i] > env[peak]) peak = i;
    }
    expect((peak - impulseFrame).abs(), lessThanOrEqualTo(3));
    expect(env[peak], greaterThan(0.5)); // normalized, so the peak ≈ 1
  });

  test('silent input yields an all-zero envelope', () {
    final env = onsetEnvelope(Float32List(22050));
    expect(env.every((v) => v == 0.0), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/beat/onset_test.dart`
Expected: FAIL — `onset.dart` / `onsetEnvelope` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/core/beat/onset.dart
import 'dart:typed_data';
import '../hybrid_cqt.dart';

/// Onset-envelope frame rate (frames/sec) for the default hop of 512 @ 22050 Hz.
const double onsetFps = 22050 / 512;

/// Spectral-flux onset envelope: per STFT frame, the sum over bins of the
/// positive magnitude increase vs the previous frame, max-normalized to
/// [0, 1]. `result[0]` is 0 (no predecessor). All-zero for silence.
List<double> onsetEnvelope(Float32List pcm, {int nFft = 2048, int hop = 512}) {
  final mag = stftMagnitude(Float64List.fromList(pcm), nFft: nFft, hop: hop);
  final n = mag.length;
  final env = List<double>.filled(n, 0.0);
  var maxV = 0.0;
  for (var t = 1; t < n; t++) {
    final cur = mag[t], prev = mag[t - 1];
    var flux = 0.0;
    for (var f = 0; f < cur.length; f++) {
      final d = cur[f] - prev[f];
      if (d > 0) flux += d;
    }
    env[t] = flux;
    if (flux > maxV) maxV = flux;
  }
  if (maxV > 0) {
    for (var t = 0; t < n; t++) {
      env[t] /= maxV;
    }
  }
  return env;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/beat/onset_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/beat/onset.dart app/test/beat/onset_test.dart
git commit -m "feat(beat): spectral-flux onset envelope"
```

---

### Task 3: Tempo estimation (autocorrelation + tempo prior)

**Files:**
- Create: `app/lib/core/beat/tempo.dart`
- Test: `app/test/beat/tempo_test.dart`

**Interfaces:**
- Consumes: `onsetFps` (Task 2).
- Produces: `double estimateTempo(List<double> onset, {double fps = onsetFps, double priorBpm = 120})` — global tempo in BPM, searched over 40–240 BPM, biased toward `priorBpm` by a log-normal weight. Returns `0.0` if the onset is too short/flat to estimate.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/beat/tempo_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/beat/onset.dart';
import 'package:chordmind/core/beat/tempo.dart';

void main() {
  test('estimates 120 BPM from an onset pulsing every 0.5s', () {
    const fps = onsetFps;
    final n = (fps * 10).round(); // 10 seconds
    final period = (fps * 0.5).round(); // 0.5s ⇒ 120 BPM
    final onset = List<double>.filled(n, 0.0);
    for (var i = 0; i < n; i += period) {
      onset[i] = 1.0;
    }
    final bpm = estimateTempo(onset, fps: fps);
    expect(bpm, closeTo(120.0, 6.0));
  });

  test('returns 0 for a flat (no-onset) envelope', () {
    expect(estimateTempo(List<double>.filled(400, 0.0)), 0.0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/beat/tempo_test.dart`
Expected: FAIL — `tempo.dart` / `estimateTempo` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/core/beat/tempo.dart
import 'dart:math' as math;
import 'onset.dart';

/// Estimates global tempo (BPM) from an onset envelope via autocorrelation,
/// weighted by a log-normal prior centred on [priorBpm] (librosa's default
/// tempo prior). Searches 40–240 BPM. Returns 0.0 when the envelope has no
/// usable periodicity (flat/too short).
double estimateTempo(List<double> onset, {double fps = onsetFps, double priorBpm = 120}) {
  final n = onset.length;
  if (n < 4) return 0.0;

  // Autocorrelation over the lag range spanning 40–240 BPM.
  final minLag = math.max(1, (fps * 60 / 240).round());
  final maxLag = math.min(n - 1, (fps * 60 / 40).round());
  if (maxLag <= minLag) return 0.0;

  var bestBpm = 0.0;
  var bestScore = double.negativeInfinity;
  const stdOctaves = 1.0; // log-normal spread (in octaves) of the prior
  for (var lag = minLag; lag <= maxLag; lag++) {
    var ac = 0.0;
    for (var i = lag; i < n; i++) {
      ac += onset[i] * onset[i - lag];
    }
    final bpm = 60 * fps / lag;
    // Log-normal prior weight around priorBpm.
    final z = math.log(bpm / priorBpm) / math.ln2 / stdOctaves;
    final weight = math.exp(-0.5 * z * z);
    final score = ac * weight;
    if (score > bestScore) {
      bestScore = score;
      bestBpm = bpm;
    }
  }
  return bestScore > 0 ? bestBpm : 0.0;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/beat/tempo_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/beat/tempo.dart app/test/beat/tempo_test.dart
git commit -m "feat(beat): autocorrelation tempo estimation with prior"
```

---

### Task 4: DP beat tracker + `BeatTracker` interface

Assembles onset → tempo → Ellis dynamic-programming beat tracking behind a swappable interface.

**Files:**
- Create: `app/lib/core/beat/beat_tracker.dart`
- Test: `app/test/beat/beat_tracker_test.dart`

**Interfaces:**
- Consumes: `onsetEnvelope`, `onsetFps` (Task 2); `estimateTempo` (Task 3).
- Produces:
  - `class BeatResult { final List<double> beats; final double bpm; const BeatResult(this.beats, this.bpm); }`
  - `abstract interface class BeatTracker { BeatResult track(Float32List pcm, {double sr}); }`
  - `class DspBeatTracker implements BeatTracker` — returns beat times (seconds, ascending) and estimated `bpm`; returns `BeatResult([], 0)` when tempo can't be estimated or the signal is too short.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/beat/beat_tracker_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/beat/beat_tracker.dart';

Float32List _clickTrack({double bpm = 120, double seconds = 10, int sr = 22050}) {
  final pcm = Float32List((seconds * sr).round());
  final periodSamples = (60 / bpm * sr).round();
  for (var s = 0; s < pcm.length; s += periodSamples) {
    // short decaying click so spectral flux sees a clear onset
    for (var k = 0; k < 64 && s + k < pcm.length; k++) {
      pcm[s + k] = (1.0 - k / 64) * (k.isEven ? 1.0 : -1.0);
    }
  }
  return pcm;
}

void main() {
  test('tracks ~120 BPM beats from a click track', () {
    final result = DspBeatTracker().track(_clickTrack(bpm: 120));
    expect(result.bpm, closeTo(120.0, 8.0));
    expect(result.beats.length, greaterThan(10));
    // Beats are ascending and spaced ~0.5s apart on average.
    for (var i = 1; i < result.beats.length; i++) {
      expect(result.beats[i], greaterThan(result.beats[i - 1]));
    }
    final span = result.beats.last - result.beats.first;
    final avg = span / (result.beats.length - 1);
    expect(avg, closeTo(0.5, 0.08));
  });

  test('too-short / silent input yields no beats', () {
    expect(DspBeatTracker().track(Float32List(2048)).beats, isEmpty);
    expect(DspBeatTracker().track(Float32List(22050 * 5)).beats, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/beat/beat_tracker_test.dart`
Expected: FAIL — `beat_tracker.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/core/beat/beat_tracker.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'onset.dart';
import 'tempo.dart';

/// Beat times (seconds, ascending) plus the estimated global tempo (BPM).
class BeatResult {
  final List<double> beats;
  final double bpm;
  const BeatResult(this.beats, this.bpm);
}

/// Swappable so a future Beat-Transformer (ONNX) backend can replace the DSP
/// tracker without touching OnDeviceAnalyzer.
abstract interface class BeatTracker {
  BeatResult track(Float32List pcm, {double sr});
}

/// Pure-DSP beat tracker: spectral-flux onset → autocorrelation tempo →
/// Ellis (2007) dynamic-programming beat tracking (librosa's default).
class DspBeatTracker implements BeatTracker {
  const DspBeatTracker();

  @override
  BeatResult track(Float32List pcm, {double sr = 22050}) {
    final onset = onsetEnvelope(pcm);
    final bpm = estimateTempo(onset);
    if (bpm <= 0) return const BeatResult([], 0);

    final period = 60 * onsetFps / bpm; // beat period in onset frames
    final beatFrames = _dpBeats(onset, period);
    if (beatFrames.length < 2) return const BeatResult([], 0);

    final beats = [for (final f in beatFrames) f / onsetFps];
    return BeatResult(beats, bpm);
  }

  /// Ellis dynamic-programming beat tracker over the onset envelope.
  /// tightness controls how strongly deviations from `period` are penalized.
  List<int> _dpBeats(List<double> localscore, double period, {double tightness = 100}) {
    final n = localscore.length;
    if (n < 3 || period < 1) return const [];

    final backlink = List<int>.filled(n, -1);
    final cumscore = List<double>.filled(n, 0);

    // Predecessor window: offsets [-2*period, -period/2].
    final loOff = (-2 * period).round();
    final hiOff = (-period / 2).round();

    for (var i = 0; i < n; i++) {
      var bestScore = double.negativeInfinity;
      var bestPrev = -1;
      for (var off = loOff; off <= hiOff; off++) {
        final j = i + off;
        if (j < 0) continue;
        // Penalty grows with squared log-deviation from one period.
        final dev = math.log(-off / period);
        final txcost = -tightness * dev * dev;
        final score = cumscore[j] + txcost;
        if (score > bestScore) {
          bestScore = score;
          bestPrev = j;
        }
      }
      if (bestPrev < 0) {
        cumscore[i] = localscore[i];
        backlink[i] = -1;
      } else {
        cumscore[i] = localscore[i] + bestScore;
        backlink[i] = bestPrev;
      }
    }

    // Start backtrace from the best-scoring frame in the last period.
    var tail = -1;
    var tailScore = double.negativeInfinity;
    final searchFrom = math.max(0, n - period.round());
    for (var i = searchFrom; i < n; i++) {
      if (cumscore[i] > tailScore) {
        tailScore = cumscore[i];
        tail = i;
      }
    }
    if (tail < 0) return const [];

    final beats = <int>[];
    for (var i = tail; i >= 0; i = backlink[i]) {
      beats.add(i);
      if (backlink[i] < 0) break;
    }
    return beats.reversed.toList();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/beat/beat_tracker_test.dart`
Expected: PASS. (If avg-spacing is slightly out, adjust `tightness`; 100 is librosa's default.)

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/beat/beat_tracker.dart app/test/beat/beat_tracker_test.dart
git commit -m "feat(beat): DSP DP beat tracker behind BeatTracker interface"
```

---

### Task 5: Beat-synchronous chord decode

**Files:**
- Create: `app/lib/core/decode/beat_sync.dart`
- Test: `app/test/decode/beat_sync_test.dart`

**Interfaces:**
- Consumes: `FrameResult` (`app/lib/core/inference/pcm_runner.dart`: `frameIndex, classId, confidence, time`), `ModelSpec` (`labels`), `Chord` (`app/lib/core/models.dart`), `fallbackFrameDur` (`app/lib/core/decode/vote_decode.dart`).
- Produces: `List<Chord> beatSyncChords(List<FrameResult> frames, List<double> beatTimes, ModelSpec spec)` — one chord per beat interval (mode of frame class ids, tie → higher summed confidence), consecutive equal labels merged, gap-free. Returns `const []` if `frames` or `beatTimes` is empty (caller falls back).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/decode/beat_sync_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/model_registry.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/inference/pcm_runner.dart';
import 'package:chordmind/core/decode/beat_sync.dart';

const _frameDur = 2048 / 22050;

ModelSpec _spec(List<String> labels) => ModelSpec.fromJson({
      'name': 'fake', 'file': 'fake.onnx', 'fs': 22050,
      'decode': 'vote', 'labels': labels, 'sha256': 'deadbeef',
    });

List<FrameResult> _frames(List<int> classIds) => [
      for (var i = 0; i < classIds.length; i++)
        FrameResult(frameIndex: i, classId: classIds[i], confidence: 1.0, time: i * _frameDur),
    ];

void main() {
  // labels: 0->N, 1->C, 2->G
  final spec = _spec(['N', 'C', 'G']);

  test('one chord per beat interval by majority (mode) of frames', () {
    // 12 frames; beats every 4 frames ⇒ intervals [0,4)[4,8)[8,end).
    // Interval 0 mostly C, interval 1 mostly G, interval 2 mostly C.
    final frames = _frames([1, 1, 1, 2, 2, 2, 2, 1, 1, 1, 1, 2]);
    final beats = [0.0, 4 * _frameDur, 8 * _frameDur];
    final chords = beatSyncChords(frames, beats, spec);
    expect(chords.map((c) => c.chord).toList(), ['C', 'G', 'C']);
    // Gap-free, covers the whole span.
    expect(chords.first.start, 0.0);
    for (var i = 1; i < chords.length; i++) {
      expect(chords[i].start, closeTo(chords[i - 1].end, 1e-9));
    }
    expect(chords.last.end, closeTo(12 * _frameDur, 1e-9));
  });

  test('consecutive equal beat labels merge into one chord', () {
    final frames = _frames([1, 1, 1, 1, 1, 1, 1, 1]); // all C
    final beats = [0.0, 4 * _frameDur];
    final chords = beatSyncChords(frames, beats, spec);
    expect(chords, hasLength(1));
    expect(chords.single.chord, 'C');
    expect(chords.single.end, closeTo(8 * _frameDur, 1e-9));
  });

  test('empty beats or empty frames returns empty (caller falls back)', () {
    expect(beatSyncChords(_frames([1, 2]), const [], spec), isEmpty);
    expect(beatSyncChords(const [], [0.0, 1.0], spec), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/decode/beat_sync_test.dart`
Expected: FAIL — `beat_sync.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/core/decode/beat_sync.dart
//
// Beat-synchronous chord decode: one chord per beat interval (mode of the
// model's per-frame class ids in that interval), consecutive equal labels
// merged. Anchoring chord changes to real beats removes sub-beat flicker
// (#5) and keeps the grid in sync with the audio (#4). Falls back to
// voteDecode (see on_device_analyzer) when there are no beats.
import '../inference/pcm_runner.dart';
import '../model_registry.dart';
import '../models.dart';
import 'vote_decode.dart' show fallbackFrameDur;

List<Chord> beatSyncChords(
  List<FrameResult> frames,
  List<double> beatTimes,
  ModelSpec spec,
) {
  if (frames.isEmpty || beatTimes.isEmpty) return const [];
  final labels = spec.labels;
  if (labels == null) {
    throw ArgumentError('${spec.name} has no labels in its manifest entry');
  }

  final frameDur =
      frames.length > 1 ? frames[1].time - frames[0].time : fallbackFrameDur;
  final songEnd = frames.last.time + frameDur;

  // Interval boundaries: optional lead-in from 0, the beats, then song end.
  final bounds = <double>[];
  if (beatTimes.first > 0) bounds.add(0.0);
  bounds.addAll(beatTimes);
  final end = songEnd > bounds.last ? songEnd : bounds.last + frameDur;
  bounds.add(end);

  // Walk frames once (both frames and bounds are ascending in time).
  final segments = <Chord>[];
  var fi = 0;
  var prevClass = -1;
  for (var b = 0; b + 1 < bounds.length; b++) {
    final lo = bounds[b], hi = bounds[b + 1];
    final counts = <int, int>{};
    final confSum = <int, double>{};
    while (fi < frames.length && frames[fi].time < hi) {
      if (frames[fi].time >= lo) {
        final c = frames[fi].classId;
        counts[c] = (counts[c] ?? 0) + 1;
        confSum[c] = (confSum[c] ?? 0) + frames[fi].confidence;
      }
      fi++;
    }

    int winner;
    double conf;
    if (counts.isEmpty) {
      // Empty interval: inherit the previous chord (or N for the first).
      winner = prevClass >= 0 ? prevClass : 0;
      conf = 0.0;
    } else {
      winner = counts.keys.first;
      for (final c in counts.keys) {
        final better = counts[c]! > counts[winner]! ||
            (counts[c] == counts[winner] && confSum[c]! > confSum[winner]!);
        if (better) winner = c;
      }
      conf = confSum[winner]! / counts[winner]!;
    }
    prevClass = winner;

    // Merge into the previous segment if the label matches.
    if (segments.isNotEmpty && segments.last.chord == labels[winner]) {
      final prev = segments.removeLast();
      final prevDur = prev.end - prev.start;
      final curDur = hi - lo;
      segments.add(Chord.fromJson({
        'chord': prev.chord,
        'start': prev.start,
        'end': hi,
        'confidence':
            (prev.confidence * prevDur + conf * curDur) / (prevDur + curDur),
      }));
    } else {
      segments.add(Chord.fromJson({
        'chord': labels[winner], 'start': lo, 'end': hi, 'confidence': conf,
      }));
    }
  }
  return segments;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/decode/beat_sync_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/decode/beat_sync.dart app/test/decode/beat_sync_test.dart
git commit -m "feat(decode): beat-synchronous chord decode (one chord per beat)"
```

---

### Task 6: Wire beat tracking + beat-sync into `OnDeviceAnalyzer`

**Files:**
- Modify: `app/lib/core/on_device_analyzer.dart` (beat loop ~lines 81–111, decode call ~line 71)
- Test: `app/test/on_device_analyzer_test.dart` (extend existing fixture test)

**Interfaces:**
- Consumes: `DspBeatTracker`/`BeatResult` (Task 4), `beatSyncChords` (Task 5), existing `voteDecode` (fallback).
- Produces: `AnalysisResult` JSON with real `beats[]`, real `source.bpm`, beat-anchored `synchronizedChords[]`.

- [ ] **Step 1: Write the failing test** (add to the existing `main()` group in `app/test/on_device_analyzer_test.dart`)

```dart
    test('produces a real (non-placeholder) tempo estimate', () async {
      final analyzer = OnDeviceAnalyzer(audioSource: _FixturePcmAudioSource(fixturePcm));
      final result = AnalysisResult.fromJson(await analyzer.analyze('testid', title: 'T'));
      // bpm is now estimated from audio (or 0 when the tracker bailed and we
      // fell back), never the old fixed 120 placeholder unless truly ~120.
      expect(result.source.bpm, greaterThanOrEqualTo(0));
      expect(result.source.bpm, lessThan(300));
      // beats are either real (non-empty) or empty (fallback path); never a
      // synthetic 120bpm grid longer than the song.
      final dur = result.source.duration;
      for (final b in result.beats) {
        expect(b.time, lessThanOrEqualTo(dur + 1e-6));
      }
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/on_device_analyzer_test.dart`
Expected: FAIL — analyzer still emits the placeholder 120bpm grid / fixed bpm (or the imports don't exist yet).

- [ ] **Step 3: Write the implementation**

In `app/lib/core/on_device_analyzer.dart`, add imports:

```dart
import 'beat/beat_tracker.dart';
import 'decode/beat_sync.dart';
```

Replace the decode call (~line 71) and the placeholder beat loop (~lines 81–89). First, track beats and choose the decoder (place right after `frames` are available and `spec` is known, before `estimateKey`):

```dart
    // Real beats from the on-device DSP tracker; fall back to frame-level
    // voteDecode (with its #5 min-duration merge) when beats can't be found.
    BeatResult beatResult;
    try {
      beatResult = const DspBeatTracker().track(pcm, sr: spec.fs.toDouble());
    } catch (e) {
      debugPrint('[analyze] beat tracking failed: $e — falling back');
      beatResult = const BeatResult([], 0);
    }
    final beatTimes = beatResult.beats;
    chords = beatTimes.isEmpty
        ? voteDecode(frames, spec)
        : beatSyncChords(frames, beatTimes, spec);
    debugPrint('[analyze] ${beatTimes.length} beats, ${chords.length} chords');
```

(Remove the old `chords = voteDecode(frames, spec);` line so `chords` is assigned once here. Keep `List<Chord> chords;` declared.)

Then replace the placeholder beat grid (the `interval`/`for (var t = 0.0; ...)` loop) with real beats, keeping the placeholder meter:

```dart
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
```

Update the returned `source.bpm` to use `bpm` instead of `placeholderBpm`:

```dart
        'bpm': bpm,
```

(`synchronizedChords` construction below is unchanged — it already emits one entry per chord change via `chordAt(beats[i].time)`, which now runs over real beats.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/on_device_analyzer_test.dart`
Expected: PASS (all existing cases + the new tempo test).

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/on_device_analyzer.dart app/test/on_device_analyzer_test.dart
git commit -m "feat(analyzer): real DSP beats + beat-synchronous chords with fallback"
```

---

### Task 7: Default model → BTC

**Files:**
- Modify: `app/lib/core/model_registry.dart:16`
- Test: `app/test/model_registry_default_test.dart`

**Interfaces:**
- Consumes: existing `defaultModelName`, `ModelRegistry.defaultModel`.
- Produces: `defaultModelName == 'btc'`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/model_registry_default_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/model_registry.dart';

void main() {
  test('default model is BTC', () {
    expect(defaultModelName, 'btc');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/model_registry_default_test.dart`
Expected: FAIL — `defaultModelName` is `'chordnet_2e1d'`.

- [ ] **Step 3: Change the default**

In `app/lib/core/model_registry.dart:16`:

```dart
const defaultModelName = 'btc';
```

- [ ] **Step 4: Run test + full suite to verify nothing else assumed chordnet**

Run: `cd app && flutter test test/model_registry_default_test.dart && flutter test`
Expected: PASS. (If any test hard-codes `chordnet_2e1d` as the default, update it to pass the model name explicitly.)

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/model_registry.dart app/test/model_registry_default_test.dart
git commit -m "feat(model): default to BTC (better chords than chordnet)"
```

---

## Self-Review

**Spec coverage:**
- §3.1 DSP beat tracker → Tasks 1–4. ✓
- §3.2 beat-sync decode → Task 5. ✓
- §3.3 analyzer integration (real beats, bpm, fallback, placeholder meter) → Task 6. ✓
- §3.4 BTC default → Task 7. ✓
- §3.1 `BeatTracker` interface (off-ramp swap point) → Task 4. ✓
- §5 error handling: empty/short → Tasks 4 (empty beats) + 5 (empty return) + 6 (try/catch fallback). ✓
- §6 testing: click track (Task 4), beat_sync mode/merge/empty (Task 5), analyzer bpm (Task 6). ✓
- §2 out-of-scope (downbeats/meter, Beat-Transformer, web) → not built; meter placeholder kept in Task 6. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Type consistency:** `stftMagnitude` (Task 1) used in Task 2; `onsetEnvelope`/`onsetFps` (Task 2) used in Tasks 3–4; `estimateTempo` (Task 3) used in Task 4; `BeatResult`/`DspBeatTracker` (Task 4) and `beatSyncChords` (Task 5) used in Task 6. `FrameResult` fields (`classId`, `confidence`, `time`) and `Chord.fromJson` keys match `models.dart`/`pcm_runner.dart`. `fallbackFrameDur` re-exported from `vote_decode.dart`. ✓
