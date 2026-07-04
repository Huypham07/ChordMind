# Plan B — Flutter On-Device Inference

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement task-by-task. Steps use checkbox (`- [ ]`).

## Status — 2026-07-04

**Phase 0 spikes ✅** B0.1 onnxruntime runs our ONNX on host (chordnet 3.8e-6, ccl bit-identical); B0.2 YouTube→PCM proven; B0.3 native hybrid_cqt feasible but incomplete (triad ok, extended-chord heads 0.85–0.89 — tracked follow-up, ccl on-device deferred).

**Phase 1 ✅ (chordnet_2e1d + btc + key)** — on-device analysis is live and **verified running on a real Android device** (Pixel 3). `SongRepository.generate` runs the on-device pipeline; each B1.1–B1.5 task was reviewed.

**Delivered beyond the original Phase-1 plan (interactive iteration):**
- **Two entry points on Home:** a YouTube link *or* a local **mp3** (shown on Home before Analyze).
- **File-mode player:** plays a local audio file via **just_audio** and syncs the chord view to its position; analysis is manual (`Sinh hợp âm` / re-analyze), same as YouTube. `AudioSource.pcmFromFile` + an `audioFilePath` path through analyzer→repository feed the same pipeline (also the documented fallback for YouTube rate-limiting, which was hit on-device).
- **Settings screen** with a chord-model picker (chordnet_2e1d / btc; chord_cnn_lstm shown "coming soon").
- **Android build fix:** `compileSdk 36` (+ per-subproject override for the `:onnxruntime` AAR pinned to 33), `minSdk 24`.
- **Chord display overhaul (replaces the A0 beat grid):** a **time-based `ChordTimeline`** driven by the model's real chord start/end times, highlighting the current chord by real playback position — chords sync to audio **without a beat model**. Short abbreviated labels (`A:min7`→`Am7`); `N`/no-chord and `X` hidden; per-change (not per-beat) segments.
- Cache prefix bumped to invalidate pre-model demo data; analyze errors surfaced in-UI + `[analyze]` stage logs.

**Known limitations / follow-ups:** no beat/meter model → the 4/4 measure grid was **dropped** in favor of the time-based timeline (real downbeats need a beat model, e.g. Beat-Transformer, a future plan); `bpm`/`timeSignature` in `AnalysisResult` remain placeholders. chord_cnn_lstm on-device blocked on finishing native hybrid_cqt (B0.3). Phase 3 (manifest-download instead of bundled models) not started. A few `RadioListTile` deprecation infos in the settings screen.

---

**Goal:** Make `SongRepository.generate(youtubeId)` run the real on-device analysis in Flutter — YouTube audio → PCM → ONNX chord inference → decoded chords + key → `AnalysisResult` JSON → cached → rendered in the existing grid. Covers all 3 exported chord models (chordnet_2e1d default, btc, chord_cnn_lstm).

**Architecture:** Replace the `generateSampleJson` stub behind `DefaultSongRepository.generate` (`app/lib/core/song_repository.dart:38`) with an `OnDeviceAnalyzer`. Models run via the `onnxruntime` Flutter package. chordnet/btc are PCM-in (CQT baked, Dart feeds PCM); chord_cnn_lstm is feature-in (Dart computes `hybrid_cqt` natively, feeds the 288-bin feature). Decode (vote / XHMM), Krumhansl key, and frame→time mapping are ported to Dart. Output is the unchanged `AnalysisResult` schema (`app/lib/core/models.dart`).

**Tech Stack:** Flutter 3.44 (installed), Dart; new deps `onnxruntime`, `youtube_explode_dart`, an audio decoder (`ffmpeg_kit_flutter` or equiv), `dart:ffi` (for native hybrid_cqt if needed). Artifacts: the ONNX + `manifest.json` from Plan A/C (`artifacts/onnx/`).

## Global Constraints

- Target **Android first** (per the on-device compute-placement decision); **web has no AI** (exclude from this path — web keeps server/sample behavior). iOS best-effort, not gated.
- Consume the committed `artifacts/onnx/manifest.json` verbatim: each entry's `input` (`pcm`|`cqtv2_feature`), `fs`, `window_samples`, `decode` (`vote`|`xhmm`), `labels`/`heads`, `feature{}`, `sha256`. Do NOT hardcode model params that live in the manifest.
- Output must be the existing `AnalysisResult` (`app/lib/core/models.dart`): `songId, source{youtubeId,title,duration,bpm,timeSignature}, key, beats[], downbeats[], chords[]{chord,start,end,confidence}, synchronizedChords[]{chord,beatIndex}, segments[], melody`. Preserve Clean-Architecture layering (features depend on `SongRepository`, not on the analyzer internals).
- **Beat model is NOT exported yet** (Plan A/C are chord-only). v1 places chords by time and leaves `beats`/`downbeats` empty or from a lightweight DSP tempo estimate; the grid renders by time. Real beat (Beat-Transformer) is a later plan — do not block on it.
- No secret keys/logic in the app beyond what's needed. Keep files focused (match existing `lib/core/*` style).
- Model files: **bundled in app assets for v1** (simplest); manifest-driven download is a later task. Note the 47MB chordnet + 27MB ccl sizes — bundle only what v1 ships and record the APK-size impact.

---

## Phase 0 — Spikes (de-risk before building)

### Task B0.1 (SPIKE): onnxruntime Flutter runs our ONNX correctly
**Goal:** Prove the `onnxruntime` Dart/Flutter package loads `chordnet_2e1d.onnx` (opset 17, LayerNormalization, baked CQT/Conv) AND `chord_cnn_lstm.onnx` (LSTM, dynamic frames, 6 outputs) and produces outputs matching a Python-generated reference for the same input. BLOCKED if an op is unsupported.

**Files:** `app/pubspec.yaml` (add `onnxruntime`), `app/test/onnx_smoke_test.dart`, plus a checked-in reference vector.

- [ ] **Step 1:** Add `onnxruntime` to pubspec; `flutter pub get`. Confirm it resolves for the host (a desktop/`flutter test` run is enough to validate op support — no Android device needed for the op-coverage question).
- [ ] **Step 2:** Generate a reference: with `scripts/export/.venv/bin/python`, run `chordnet_2e1d.onnx` on a fixed input (e.g. the 219136-sample zeros window, or a fixture's PCM window) via onnxruntime-python, save input+output arrays to a small `.json`/`.bin` asset under `app/test/fixtures/`.
- [ ] **Step 3:** Dart test: load the ONNX, feed the same input, assert outputs match the reference within 1e-3 (argmax equal). Repeat for `chord_cnn_lstm.onnx` (feature-in: feed a saved 288-bin feature, check 6 outputs).
- [ ] **Step 4:** Run `flutter test test/onnx_smoke_test.dart`. Must pass. If an op is unsupported on the package's runtime, report BLOCKED with the op name — controller decides (different ORT build / op workaround).
- [ ] **Step 5:** Commit `spike(app): onnxruntime runs chordnet + ccl ONNX, matches python reference`.

### Task B0.2 (SPIKE): YouTube audio → mono 22050 PCM in Flutter
**Goal:** From a `youtubeId`, obtain decoded mono float32 PCM at 22050 Hz on-device. BLOCKED if extraction/decoding isn't viable on the target.

**Files:** `app/pubspec.yaml` (add `youtube_explode_dart` + a decoder), `app/lib/core/audio_source.dart`, `app/test/audio_source_test.dart` (or an integration harness).

- [ ] **Step 1:** Add `youtube_explode_dart` (audio-only stream URL) + an audio decoder capable of compressed→PCM (evaluate `ffmpeg_kit_flutter_new` or `just_audio`+platform decode). Document the choice + license/size.
- [ ] **Step 2:** Implement `AudioSource.pcm(youtubeId) -> Future<Float32List>` (mono, resampled to 22050). Mirror ChordMiniApp's client-side extraction approach conceptually.
- [ ] **Step 3:** Verify on a real short video id that it returns a plausibly-sized PCM buffer (len ≈ duration*22050) and that a known tone maps to the right CQT bin (sanity, not bit-exact).
- [ ] **Step 4:** Run the test/harness. BLOCKED if extraction is blocked (throttling/ToS/format) — controller decides (fallback: local file picker per the design's alternative).
- [ ] **Step 5:** Commit `spike(app): youtube audio to mono 22050 PCM`.

### Task B0.3 (SPIKE): native hybrid_cqt for chord_cnn_lstm
**Goal:** Reproduce `librosa.core.hybrid_cqt` (bins_per_octave=36, fmin=F#0, n_bins=288, hop=512, tuning=None, magnitude) on-device closely enough that the ccl 6-head argmax matches the reference. This is the accepted hard dependency. BLOCKED/defer if it can't hit parity — ccl then ships later; chordnet/btc proceed regardless.

**Files:** `app/lib/core/hybrid_cqt.dart` (Dart) and/or `app/native/` (C via FFI), `app/test/hybrid_cqt_test.dart`, a Python-generated reference feature asset.

- [ ] **Step 1:** Read `reference/chord-cnn-lstm-model/` librosa `hybrid_cqt` path (tuning estimation + per-octave pseudo/full-CQT switch). Decide Dart-port vs C/Rust FFI vs vendoring a C CQT.
- [ ] **Step 2:** Generate a reference feature: `_cqt_v2(fixture, 22050)` (from `scripts/export/load_ccl.py`) → save the 288-bin array as an asset.
- [ ] **Step 3:** Implement `hybridCqt(pcm) -> Float32List[frames*288]`; test asserts per-head argmax of `ccl.onnx(nativeFeature)` matches the saved reference (feed the native feature into the B0.1 ORT path) on the rich-triad + C9 fixtures at ≥0.99.
- [ ] **Step 4:** Run test. If parity unreachable, report DONE_WITH_CONCERNS/BLOCKED with numbers — controller decides (ship ccl feature-in with a documented lower bar, or defer ccl to a later plan).
- [ ] **Step 5:** Commit `spike(app): native hybrid_cqt for chord-cnn-lstm`.

> After B0.1–B0.3, the controller reviews spike outcomes and finalizes Phase 1/2 task code before dispatching them (the build tasks below are structured; their exact Dart is finalized against the spike APIs).

---

## Phase 1 — PCM-in analysis (chordnet_2e1d + btc + key)

### Task B1.1: Model registry from manifest + bundled assets
**Files:** `app/assets/models/` (bundle `chordnet_2e1d.onnx`, `btc.onnx`, `manifest.json`), `app/pubspec.yaml` (assets), `app/lib/core/model_registry.dart`, test.
- Load `manifest.json`; expose `ModelSpec` per entry (name, input, fs, window_samples, decode, labels/heads, feature). Verify sha256 of bundled files against manifest. Provide the active-model selection (default `chordnet_2e1d`).

### Task B1.2: Windowed inference runner (PCM-in)
**Files:** `app/lib/core/inference/pcm_runner.dart`, test.
- Slide the model's `window_samples` window over the PCM (hop = window or overlap per model), run ORT per window, collect per-frame 170-logits across the song. Output `List<int>` argmax per frame + confidences + frame times (frame_dur = hop_length/fs from manifest).

### Task B1.3: Vote decode → chords
**Files:** `app/lib/core/decode/vote_decode.dart`, test.
- Port the sliding-window majority/vote + label mapping (manifest `labels`) → merge consecutive equal labels into `Chord{chord,start,end,confidence}`. Unit-test against a hand-built frame sequence.

### Task B1.4: Krumhansl key
**Files:** `app/lib/core/decode/key_krumhansl.dart`, test.
- Aggregate a 12-bin chroma from the chord frames (or from CQT), correlate with Krumhansl-Schmuckler major/minor profiles → `key` string. ~40 lines + a test on a known-key chroma.

### Task B1.5: Assemble AnalysisResult + wire into generate()
**Files:** `app/lib/core/on_device_analyzer.dart`, modify `app/lib/core/song_repository.dart` (`generate` → call analyzer), test.
- `OnDeviceAnalyzer.analyze(youtubeId, title) -> AnalysisResult`: AudioSource.pcm → runner → vote decode → key → build `AnalysisResult` (chords + key + source{duration from PCM len, bpm placeholder, timeSignature 4}; beats/downbeats empty per constraint; chords placed by time). Persist via existing `LocalStore`. Replace `generateSampleJson` call. Keep the `SongRepository` interface unchanged.
- Progress/errors surfaced to `player_screen`'s existing `_generate` flow.

## Phase 2 — chord_cnn_lstm on-device (feature-in)

### Task B2.1: hybrid_cqt wired + ccl inference + XHMM decode
**Files:** `app/lib/core/inference/ccl_runner.dart`, `app/lib/core/decode/xhmm_decode.dart`, vendored templates under `app/assets/models/ccl/` (the `decode_assets` from the CCL manifest entry), tests.
- Use B0.3 `hybridCqt` → ccl ONNX → 6 head probs → port XHMM Viterbi over the vendored `*_chord_list.txt` templates + `complex_chord` head combination → `Chord[]`. Register `chord_cnn_lstm` as a selectable model in the registry (decode=xhmm). Gate behind the model selection UI.

## Phase 3 — Model selection UI + manifest-download (deferred polish)
- Model picker (chordnet/btc/ccl) in the player; switch → re-analyze.
- Move models from bundled assets to first-run manifest download (sha256-verified) into app documents dir, to shrink the APK. (Design §6.)

## Self-Review
- **Spec coverage:** on-device generate() seam (B1.5), 3 models (B1.1/B2.1), manifest-driven (B1.1), decode ports (B1.3/B1.4/B2.1), audio source (B0.2), ORT feasibility (B0.1), native hybrid_cqt (B0.3/B2.1). Beat explicitly deferred (constraint). Web excluded (constraint).
- **Risk front-loading:** the three genuine unknowns (ORT op support, YouTube→PCM, native hybrid_cqt) are Phase-0 spikes with BLOCKED exits, before any build task.
- **Decomposition:** Phase 1 (chordnet/btc+key) is independently shippable (a working on-device app) without Phase 2 (ccl). If Phase 0.3 blocks, Phase 1 still ships.
- **Placeholders:** build-task Dart is finalized against spike APIs (noted); no fabricated code committed ahead of the spike that proves the API. Spikes are real investigate-and-prove tasks, not TODOs.
