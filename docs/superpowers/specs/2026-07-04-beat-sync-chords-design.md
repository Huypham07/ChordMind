# ChordMind — Beat Detection (DSP) + Beat-Synchronous Chords

> Fixes the "junk chord flicker" (#5) and "unstable chord↔audio sync" (#4)
> by estimating **real beats on-device** and decoding **one chord per beat**
> instead of per frame. Pure-Dart DSP beat tracker; no new model, no new
> dependency. Beat-Transformer (ONNX) is the documented later off-ramp if
> DSP beats prove inaccurate.

## 1. Motivation

The current pipeline decodes chords **per frame** (~0.093s), majority-filters
flicker, then merges equal runs (`voteDecode`). Beats are a **placeholder
120bpm grid** (`on_device_analyzer.dart`), and `bpm`/`timeSignature` are
placeholders per the 2026-07-04 on-device plan (beat model deferred).

Two consequences the user hit:

- **Noise (#5):** frame-level decode still yields sub-0.3s chord changes
  (e.g. `D → D7 → G` in a blink). The min-duration merge added on
  `feat/chord-denoise` mitigates this but is a frame-domain heuristic, not
  aligned to musical structure.
- **Sync (#4):** chord changes don't land on beats, and the fake 120bpm grid
  makes the grid highlight drift against the audio.

Both are the same root cause: **no beat grid, and chords not anchored to
it.** The musically correct fix is **beat-synchronous chord estimation** —
one chord per beat interval — which requires **real beat boundaries**.

## 2. Scope

**In:**
- Pure-Dart DSP beat tracker producing real beat times + estimated tempo.
- Beat-synchronous chord decode (mode of frame labels per beat interval).
- Integration into `OnDeviceAnalyzer` (real `beats[]`, real `bpm`,
  beat-anchored `synchronizedChords[]`).
- Default model switched to **BTC** (user reports better chords than
  ChordNet).
- `BeatTracker` interface so the backend can later swap to Beat-Transformer.

**Out (deferred):**
- Real downbeats / meter detection. `beatNum` stays a placeholder 1..4
  cycle; `timeSignature` stays 4. Beat-sync chords only need beat
  boundaries, not downbeats.
- Beat-Transformer ONNX export + its DBN decoder (reference uses madmom,
  Cython/Python-only — a separate large plan). This is the escalation path.
- Web (analysis stays mobile-only, per existing constraints).

## 3. Components

### 3.1 `core/beat/beat_tracker.dart` — DSP beat tracking

Interface (for future swap):

```dart
abstract interface class BeatTracker {
  /// Beat times in seconds (ascending) + estimated tempo (BPM).
  BeatResult track(Float32List pcm, {double sr});
}

class BeatResult {
  final List<double> beats; // seconds
  final double bpm;         // estimated global tempo
}
```

`DspBeatTracker implements BeatTracker` — the Ellis (2007) dynamic-programming
beat tracker, librosa's default algorithm:

1. **Onset envelope.** Short-time magnitude spectrum via the STFT/FFT already
   in `hybrid_cqt.dart` (reuse — do not write a second FFT). Window ~2048,
   hop ~512 (⇒ ~86 fps at 22050 Hz). Spectral flux = sum over bins of the
   positive first-difference of magnitude across frames; normalize.
2. **Tempo.** Autocorrelation of the onset envelope, weighted by a log-normal
   prior centred ~120 BPM; take the peak lag ⇒ global BPM ⇒ target beat
   period in onset frames.
3. **Beat DP.** Maximize `Σ onset[beat] − α · Σ penalty(Δ from period)` via
   forward cumulative-score + backtrace (Ellis). Convert beat frames back to
   seconds.

Returns `BeatResult(beats, bpm)`. If the signal is too short to estimate
tempo (fewer than a couple of periods), returns `beats: []` so callers fall
back (see §3.3). No downbeats.

`// ponytail: energy/spectral-flux onset is the lazy-but-standard choice;
upgrade to a mel/percussive onset only if beats prove weak on real songs.`

### 3.2 `core/decode/beat_sync.dart` — beat-synchronous decode

```dart
List<Chord> beatSyncChords(
  List<FrameResult> frames,
  List<double> beatTimes,
  ModelSpec spec,
);
```

Algorithm:
1. Build beat intervals: `[beatTimes[i], beatTimes[i+1])` for each `i`;
   prepend `[0, beatTimes.first)` if it starts after 0 (lead-in), and set
   the final interval's end to the song end (last frame time + frameDur).
2. For each interval, gather frames whose `time` falls inside it and take the
   **mode** of `classId` (tie → the class with the higher summed
   confidence). Confidence = mean confidence over the winning class's frames.
   An empty interval (no frames) inherits the previous chord (or `N` if
   first).
3. Emit one `Chord` per interval (`start`/`end` = interval bounds), then
   **merge consecutive equal labels** into single `Chord`s (same run-merge as
   `voteDecode`, duration-weighted confidence). Timeline stays gap-free.

### 3.3 Integration — `on_device_analyzer.dart`

Replace the placeholder beat loop and `voteDecode` call:

```
pcm → runner → frames
             ├─ BeatTracker.track(pcm) → beatTimes, bpm
             └─ beatTimes.isEmpty
                  ? voteDecode(frames, spec)          // #5 min-duration fallback
                  : beatSyncChords(frames, beatTimes, spec)
```

- `beats[]` = beatTimes with `beatNum` cycling 1..4 (placeholder meter);
  `downbeats` = the `beatNum == 1` times (placeholder until a meter model).
- `source.bpm` = estimated tempo (real, not placeholder); `timeSignature`
  stays 4.
- `synchronizedChords[]` = one entry per chord **change**, `beatIndex` = the
  index of the beat where the change lands — now on **real** beats, so the
  grid highlight tracks the audio (#4) and there is no sub-beat flicker (#5).

`key` estimation (`estimateKey`) is unchanged; it consumes the final chord
list.

### 3.4 Default model → BTC

`model_registry.dart`: `defaultModelName = 'btc'`. BTC is already bundled
(`assets/models/btc.onnx`, manifest entry present). One-line change; no other
wiring.

## 4. Data flow (unchanged contract)

Still emits the exact `AnalysisResult` JSON. Consumers (chord grid, timeline)
are untouched — they already render from `beats`/`chords`/`synchronizedChords`
by time. The only observable change is that those arrays now carry real,
beat-anchored data instead of a fake grid.

## 5. Error handling / edge cases

- **Too-short / silent audio:** `track` returns empty beats → fall back to
  `voteDecode` (which already handles empty/short frame lists).
- **Beat tracker throws:** analyzer catches, logs, falls back to
  `voteDecode`. Analysis must never fail because beat tracking did.
- **Empty beat interval:** inherits previous chord (§3.2), never emits a gap.
- **Tempo estimate absurd (e.g. >300 or <40 BPM):** clamp/reject → treat as
  failed tempo → empty beats → fallback.

## 6. Testing

Runnable checks (no framework beyond `flutter_test`):

- **beat_tracker_test:** synthesize a click track (unit impulses every 0.5s
  ⇒ 120 BPM) in Float32 PCM; assert detected `bpm` ≈ 120 (±~5%) and beat
  spacing ≈ 0.5s within tolerance. Assert too-short input ⇒ empty beats.
- **beat_sync_test:** given hand-built `frames` and a known `beatTimes` grid,
  assert one chord per interval chosen by mode, equal-label merge collapses
  runs, empty-interval inherits previous, and empty `beatTimes` returns
  empty (caller falls back).
- **on_device_analyzer_test:** the existing fixture test keeps its relaxed
  bounds (`synchronizedChords` ≤ beats); add an assertion that `bpm` is now a
  plausible estimate (> 0, within a sane range) rather than the fixed
  placeholder.

## 7. Off-ramp

If DSP beats are inaccurate on real songs, escalate to **Beat-Transformer →
ONNX** behind the same `BeatTracker` interface (its own plan): export the
neural beat/downbeat model like the chord models, and reimplement the beat
decoder (reference uses madmom's DBN) in Dart or use peak-picking on the beat
activation. The interface means `OnDeviceAnalyzer` doesn't change.

## 8. Relationship to prior work

- Builds on `feat/chord-denoise` (#5): the min-duration merge stays as the
  **no-beats fallback**, so #5 is not wasted.
- Supersedes the placeholder 120bpm grid from the 2026-07-04 on-device plan,
  fulfilling that plan's stated "real beats need a beat model, later" note
  with the lazy DSP option first.
