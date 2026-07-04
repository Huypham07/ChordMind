# On-Device Base Analysis Pipeline — Design

> Date: 2026-07-03 · Phase: roadmap **A1** (fill `ModelSlot` with reference models)
> Status: approved design, pre-plan. Supersedes the "server ml_worker / TFLite"
> wording in `research_proposal.md` §4/§6 for the base pipeline (see §9).

## 1. Goal

Build a **base analysis pipeline that runs entirely on-device (Flutter)** using the
existing **reference models**, before any self-optimized model (H1a quantized /
H2 MuQ / H1b generative). The base is the reference-quality baseline everything
else is compared and swapped against.

Steps in scope (user-confirmed full pipeline): **beat+downbeat, chord, key,
segmentation, melody**. Delivered in phases (§8) so chord+key ship first.

## 2. Decisions (locked)

| Decision | Choice | Reason |
|---|---|---|
| Where it runs | **On-device (Flutter)** | Matches on-device compute-placement decision; server-side processing stays deferred. |
| Runtime | **ONNX Runtime** (`onnxruntime` Flutter) | All reference checkpoints are PyTorch → direct `torch.onnx` export. TFLite would need a lossy ONNX→TF→TFLite chain. |
| Feature extraction | **Baked into the ONNX graph** | STFT is a native ONNX op; CQT/mel = precomputed constant matmul. Dart feeds raw PCM only → guaranteed parity with training, zero DSP in Dart. |
| Model I/O contract | **Waveform-in, logits-out** | Dart decodes audio → mono PCM (per-model fs) → ORT → light post-proc. |
| Model swapping | **`ModelSlot` per step, multiple selectable options** | Same abstraction that lets H1a/H2 variants drop in with no pipeline change. |
| Output schema | **Existing `AnalysisResult`** (`server/app/domain/entities.py`) | App local store + grid renderer unchanged. |

## 3. Model selection per step

The chord slot ships **all three** reference models as user-selectable options
(driven by `manifest.json`); others default to one with the slot open for more.

| Step | Options (default first) | Notes / export path |
|---|---|---|
| **Chord** | **chord-cnn-lstm (large-voca)** · BTC (`btc_model_best.pth`) · ChordNet 2E1D (`2e1d_model_best.pth`) | Default = best overall quality (ChordMiniApp author's pick). BTC = accuracy ref. 2E1D = smallest (2.2M) for weak phones. CQT baked; decode ported to Dart (HMM Viterbi / CRF / Gaussian+vote). |
| **Beat + downbeat** | **Beat-Transformer** | Best beat quality. ⚠️ needs Spleeter demix input — resolved in Phase 2 (§8, §7 risk 1). |
| **Key** | **Krumhansl-Schmugler** (rule-based on chroma) | No model, ~40 lines Dart, already useful for transpose. |
| **Segmentation** | **SongFormer** | `torch.onnx`; Phase 3. |
| **Melody** | **SheetSage** | Heaviest; Phase 3, may not be real-time pre-optimization. |

Checkpoints already on disk in `reference/` (BTC, 2E1D, chord-cnn-lstm
`checkpoint.bin`, Beat-Transformer, SongFormer, SheetSage).

## 4. Conversion workflow — `scripts/export/`

One script per model. Each:

1. Load reference checkpoint (Python, torch).
2. Wrap so the graph is `PCM → [baked STFT/CQT/mel] → model → logits`.
3. `torch.onnx.export`, opset ≥ 17 (native STFT op).
4. **Parity gate (the runnable check):** run original librosa+torch vs exported
   ONNX on 3 clips; assert max logit diff < ε. Fails loudly if export drifts.
5. Emit `model.onnx` + a `manifest.json` entry:
   `{name, step, url, sha256, version, fs, input_shape, decode}`.

## 5. On-device pipeline flow (Dart)

```
local audio file
  → decode to mono PCM (resample per model fs)
  → ORT beat.onnx    → DBN decode        → beats / downbeats
  → ORT chord.onnx   → decode (per model)→ chords
  → chroma → Krumhansl                    → key
  → (Phase 3) segment.onnx, melody.onnx
  → assemble AnalysisResult (unchanged schema)
  → cache on device → render existing beat/chord grid
```

Post-processing ported to Dart, each small + deterministic + unit-tested:
chord-label mapping, HMM Viterbi (chord-cnn-lstm), CRF / Gaussian-smooth+
sliding-window vote (BTC / 2E1D), beat DBN, Krumhansl key.

## 6. Storage (mobile-first)

- **Models** — not bundled in the binary (50–100MB+, re-exported often). Fetched
  on first run into the app documents dir, driven by `manifest.json`
  (name→url→sha256→version). App compares manifest version, downloads/updates
  lazily, verifies sha256. Ships new checkpoints without an app release.
- **Analysis cache** — per-song `AnalysisResult` JSON keyed by `youtubeId`, in the
  existing local-first store (sqflite / JSON files). This *is* the cache; server
  version-sync stays deferred.
- **Audio** — already local; PCM for inference decodes from the same file.

## 7. Risks & ceilings

1. **Beat-Transformer needs Spleeter 5-stem demix input** — a whole source-
   separation model to also run on-device. Biggest blocker. Options: (a) export a
   light 2-stem Spleeter to ONNX too, (b) feed raw mix (accuracy drop), (c) defer.
   **Resolution: phase it (Phase 2), don't block chord.** Pick a/b/c then.
2. **First-run download + first-inference latency** — warm ORT session once, show
   progress on first analyze.
3. **SheetSage melody heavy** — last; may not be real-time pre-optimization.
4. **chord-cnn-lstm decode complexity** — structure decomposition + HMM is more
   Dart than a plain Transformer; mitigated by the parity gate + unit tests.

## 8. Phasing

- **Phase 1** — Chord (3 selectable options) + Key on-device: waveform-in ONNX
  export, Dart decode/post-proc, manifest download, cache, render. No Spleeter.
- **Phase 2** — Beat + downbeat; resolve the Spleeter decision (§7.1).
- **Phase 3** — Segmentation (SongFormer) + Melody (SheetSage).

## 9. Relationship to existing docs

- `research_proposal.md` §4 lists the same steps; §6/§9 assume server `ml_worker`
  + TFLite. For the **base**, compute moves on-device and runtime is **ONNX**.
  Server `ml_worker` is not deleted — it stays deferred for optional server-side
  reprocessing later. Update those two lines when this lands.
- `ROADMAP_LEARNING.md` A1 "cắm model bước 1-6": this is that, on-device.
- `ModelSlot` / `AnalysisResult` in `server/app/` already define the contract;
  the app side mirrors the same slot pattern.
