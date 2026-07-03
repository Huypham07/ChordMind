# chord-cnn-lstm On-Device ONNX — Implementation Plan (Plan C)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add chord-cnn-lstm as a third on-device chord option: a `PCM → per-frame decomposition-head probabilities` ONNX, with a parity gate proving it matches the reference Python inference. XHMM decode is deferred to Plan B (Dart), same as the other models' decode.

**Architecture:** chord-cnn-lstm (ISMIR2019 large-voca) is a *different* stack from ChordNet/BTC: input is `librosa.core.hybrid_cqt` (288 bins, 36/oct, F#0, hop 512), the net is CNN→BiLSTM→FC producing **6 softmax heads** (triad/root, bass, 7th, 9th, 11th, 13th), and final labels come from an XHMM Viterbi decode over templates. It lives in a custom `NetworkBehavior`/`entry` framework in `reference/chord-cnn-lstm-model/`, checkpoint `reference/ChordMiniApp/python_backend/models/Chord-CNN-LSTM/*` (or `python_backend/checkpoint.bin`).

**Tech Stack:** Python 3.9 venv `scripts/export/.venv` (torch, nnAudio, librosa, onnx, onnxruntime), reference code under `reference/chord-cnn-lstm-model/`.

## Global Constraints

- Runtime = ONNX Runtime; export via `torch.onnx.export`, opset ≥17. Same toolchain dir `scripts/export/`.
- On-device feature extraction must be baked into the graph (PCM in) OR, if `hybrid_cqt` proves un-bakeable, an explicitly-documented alternative decided at Task 2 — no silent divergence.
- Parity gate = per-frame **argmax agreement == 1.0** on the realistic fixtures, computed **per decomposition head** (all 6 heads must agree), since there is no single 170-class output. Raw prob/logit diff is only a loose sanity ceiling. This mirrors the argmax-agreement decision made for ChordNet/BTC.
- Reuse existing infra where it fits (`config.py`, fixtures, manifest, CLI `MODELS`); do not duplicate.
- Artifacts under `artifacts/onnx/` (gitignored). `manifest.json` committed. Never commit `.onnx`.
- CQTV2 params verbatim (`reference/chord-cnn-lstm-model/extractors/cqt.py:44`): `librosa.core.hybrid_cqt(music, bins_per_octave=36, fmin=librosa.note_to_hz('F#0'), n_bins=288, tuning=None, hop_length=512)`, magnitude (`abs`), float32; confirm the sample rate from the reference `entry.prop`/music loader in Task 1.

---

### Task 1 (SPIKE): Load the net + reproduce reference inference in Python

**Goal:** Prove we can construct the chord-cnn-lstm net, load `checkpoint.bin`, and reproduce the reference `inference()` 6-head outputs on a fixture — outside its `chord_recognition` monolith. This is a feasibility gate; if the net can't be cleanly separated from the `entry`/`NetworkBehavior` framework, STOP and report BLOCKED with specifics.

**Files:**
- Create: `scripts/export/load_ccl.py` (ccl = chord-cnn-lstm)
- Test: `scripts/export/tests/test_load_ccl.py`

**Interfaces:**
- Produces: `load_ccl() -> CCLBundle` with `.net` (torch nn.Module, eval), `.sample_rate: int`, plus a `reference_probs(net, wav_path) -> tuple[np.ndarray, ...]` helper returning the 6 head arrays exactly as the reference `ChordNet.inference` does (via the reference `hybrid_cqt` + the net's internal sub-band slice `x[:, SHIFT_HIGH*SHIFT_STEP : ...+SPEC_DIM]`).

- [ ] **Step 1:** Read `reference/chord-cnn-lstm-model/chord_recognition.py`, `chordnet_ismir_naive.py` (`ChordNet`, `NetworkBehavior`, `CNNFeatureExtractor`, `SHIFT_HIGH/SHIFT_STEP/SPEC_DIM`, `chord_limit`), and `reference/ChordMiniApp/python_backend/services/detectors/chord_cnn_lstm_detector.py` to learn the exact model class, constructor args (`triad_only`, `cross_subpart_counter=None`), and how `NetworkBehavior` loads `checkpoint.bin`. Confirm the sample rate used to load audio.
- [ ] **Step 2:** Write a failing test asserting `load_ccl().net` is an eval nn.Module and `reference_probs(net, fixture)` returns 6 arrays whose frame counts match and whose per-frame argmax is stable (non-degenerate) on a realistic fixture.
- [ ] **Step 3:** Implement `load_ccl` reusing the reference's own load path (mirror the detector), adding `reference/chord-cnn-lstm-model` to `sys.path`; install any transitively-required deps into the venv and add them to `scripts/export/requirements.txt` (expect surprises, like the seaborn issue in Plan A).
- [ ] **Step 4:** Run the test with `scripts/export/.venv/bin/python -m pytest scripts/export/tests/test_load_ccl.py -v`; it must pass against the real checkpoint.
- [ ] **Step 5:** Commit `feat(export): load chord-cnn-lstm net + reproduce reference 6-head inference`.

> If Step 1/3 reveals the net cannot be run without the full `entry` framework (e.g. feature I/O tightly bound), report BLOCKED — the controller decides whether to vendor a minimal shim or reconsider the approach.

---

### Task 2 (SPIKE): hybrid_cqt bakeable front-end feasibility

**Goal:** Decide HOW the 288-bin `hybrid_cqt` front-end runs on-device, and prove the net's 6-head argmax is preserved under that choice.

**Files:**
- Create: `scripts/export/ccl_frontend.py`
- Test: `scripts/export/tests/test_ccl_frontend.py`

**Interfaces:**
- Produces: `CCLFrontend(torch.nn.Module)`: `forward(pcm) -> Tensor` matching the reference `hybrid_cqt` feature (288 bins, magnitude, float32) closely enough that feeding it to `.net` preserves per-frame argmax on all 6 heads vs the reference path.

- [ ] **Step 1:** Determine the approach, in order of preference: (a) nnAudio CQT configured to approximate `hybrid_cqt` (36/oct, F#0, 288 bins) — `hybrid_cqt` switches between pseudo- and full-CQT per octave, so an nnAudio full-CQT may differ; (b) precompute librosa's CQT basis as a fixed conv/matmul baked into the graph; (c) if neither preserves argmax, document that CQTV2 must be computed natively on-device (native FFI) and export the net starting at the feature input instead. Pick the first that works.
- [ ] **Step 2:** Write a failing test: `CCLFrontend()(pcm)` output shape is `[.., 288]`; and feeding it through `load_ccl().net` yields per-frame argmax equal to the reference `reference_probs` on ALL 6 heads for a realistic fixture (tolerance: argmax equality, not bit-parity).
- [ ] **Step 3:** Implement the chosen front-end.
- [ ] **Step 4:** Run the test; it must pass. If only (c) is viable, record that decision here and adjust Task 3 to export from the feature input (the CLI/manifest must then note `input: "cqtv2_feature"` not `"pcm"`).
- [ ] **Step 5:** Commit `feat(export): chord-cnn-lstm hybrid_cqt front-end (argmax-preserving)`.

---

### Task 3: Export chord-cnn-lstm to ONNX (6-head output)

**Files:**
- Create: `scripts/export/export_ccl.py`
- Test: `scripts/export/tests/test_export_ccl.py`

**Interfaces:**
- Produces: `export_ccl(out_path) -> Path` — ONNX graph `PCM (or feature per Task 2) → 6 head tensors`. Wrap `CCLFrontend` + `net` + the net's internal sub-band slice; output the 6 head logits (pre-softmax is fine; argmax is unaffected). Handle the net's fixed window/`SPEC_DIM` slice inside the graph.

- [ ] **Step 1:** Failing test: load the exported ONNX in onnxruntime, feed a fixture-length PCM (or feature), assert it returns 6 outputs with the expected class dims (`triad_limit*12+2+12`, bass, 7/9/11/13 sizes from `chord_limit`).
- [ ] **Step 2:** Run to confirm failure.
- [ ] **Step 3:** Implement `export_ccl` (LSTM exports fine to ONNX opset ≥17; if the net's `init_hidden`/dynamic seq causes trace issues, export a fixed window like the ChordNet 108-frame approach and document the window).
- [ ] **Step 4:** Run; assert shapes.
- [ ] **Step 5:** Commit `feat(export): export chord-cnn-lstm to ONNX (6 decomposition heads)`.

---

### Task 4: Parity gate (per-head argmax) + manifest + CLI

**Files:**
- Modify: `scripts/export/parity_check.py` (add `ccl_head_agreement(onnx, wav) -> tuple[float,...]`)
- Modify: `scripts/export/manifest.py` (labels: emit the head layout / class sizes, `decode="xhmm"`), `scripts/export/__main__.py` (`MODELS["chord_cnn_lstm"]`)
- Test: `scripts/export/tests/test_parity_ccl.py`

**Interfaces:**
- Produces: `ccl_head_agreement(onnx_path, wav)` returning per-head argmax-agreement (ONNX vs reference `reference_probs`); CLI gate fails unless every head == 1.0 on each clip.

- [ ] **Step 1:** Failing test: `ccl_head_agreement(onnx, fixture)` returns 6 values; assert all == 1.0 on the realistic fixtures.
- [ ] **Step 2:** Run to confirm failure.
- [ ] **Step 3:** Implement the per-head agreement; wire `chord_cnn_lstm` into `MODELS` with `decode="xhmm"`; extend the manifest entry to describe the 6-head layout + class sizes (the app needs this to run XHMM). Emit `input` type per Task 2's decision.
- [ ] **Step 4:** Run `scripts/export/.venv/bin/python -m scripts.export chord_cnn_lstm` — must exit 0, all heads argmax=1.0 on all clips, write `artifacts/onnx/chord_cnn_lstm.onnx` + manifest entry. Run the FULL `scripts/export/tests/` suite (no regressions to ChordNet/BTC).
- [ ] **Step 5:** Commit `feat(export): chord-cnn-lstm parity gate + manifest + CLI option`.

> XHMM Viterbi decode over the 6 heads (templates in `reference/chord-cnn-lstm-model/data/*_chord_list.txt` + `complex_chord.py`) is NOT in this plan — it is on-device decode, ported to Dart in Plan B alongside the other models' decode. This plan stops at faithful head-probability export.

## Self-Review

- **Spec coverage:** on-device ONNX (T3), baked/decided front-end (T2), parity per-head argmax (T4), manifest+CLI (T4), reuse of infra (T1/T4). XHMM decode explicitly deferred to Plan B.
- **Risk front-loading:** T1 and T2 are spikes with explicit BLOCKED exits — feasibility (framework separability, hybrid_cqt bakeability) is proven before any export code is written.
- **Placeholders:** none; each task has concrete files, interfaces, and runnable commands. The two spikes name the exact reference files/symbols to read.
- **Consistency:** `load_ccl`/`CCLBundle`/`reference_probs` (T1) → `CCLFrontend` (T2) → `export_ccl` (T3) → `ccl_head_agreement`/`MODELS["chord_cnn_lstm"]`/`decode="xhmm"` (T4) used consistently.
