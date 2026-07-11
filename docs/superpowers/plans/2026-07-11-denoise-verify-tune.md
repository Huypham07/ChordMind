# Denoise Verify + Tune (#5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Codify an automated noise-metric gate proving chord denoise is sufficient, and apply one evidence-backed knob change (vote `minChordDur` 0.3→0.5) in Dart+Python parity.

**Architecture:** Add a pure-function `noise_metrics.py` (chord list → short-segment fraction, flicker-per-minute). Bump the vote-decode fallback's default min chord duration to 0.5s on both sides. Add a regression test that runs the pipeline on a 30s slice of the in-repo real clip and asserts the metrics.

**Tech Stack:** Python 3.12 (numpy, onnxruntime, soundfile), Dart (Flutter test).

## Global Constraints

- Base branch: `feat/song-search`. Commit messages: plain, NO Co-Authored-By trailer.
- Parity: the vote `minChordDur` default must be 0.5 in BOTH `app/lib/core/decode/vote_decode.dart` and `server/app/infrastructure/analysis/vote_decode.py`.
- Noise-metric thresholds (verbatim): short-segment threshold = 0.5s; a "flicker" = a segment shorter than 0.5s whose two neighbors have the same chord label (A→B→A).
- Beat-sync path is NOT changed (already measured 0 flicker / 0 short across the whole song).
- Real-clip fixture: `reference/BTC-ISMIR19/test/example.mp3` (already in repo — decode + slice first 30s at runtime; do NOT commit new audio).
- Gate must skip when `btc.onnx` is absent (reuse `server/tests/conftest.py` guard) or the mp3 can't be decoded.

---

### Task 1: Noise metrics module

**Files:**
- Create: `server/app/infrastructure/analysis/noise_metrics.py`
- Test: `server/tests/analysis/test_noise_metrics.py`

**Interfaces:**
- Consumes: `Chord` from `server/app/infrastructure/analysis/chords.py` (fields `chord:str, start:float, end:float, confidence:float`).
- Produces:
  - `short_fraction(chords: list[Chord], thresh: float = 0.5) -> float` — fraction of segments with `end-start < thresh` (0.0 for empty input).
  - `flicker_per_min(chords: list[Chord], duration: float, thresh: float = 0.5) -> float` — count of indices `i` (1..n-2) where `chords[i-1].chord == chords[i+1].chord` and `chords[i].end-chords[i].start < thresh`, divided by `duration/60` (0.0 when `duration<=0`).

- [ ] **Step 1: Write the failing tests**

```python
# server/tests/analysis/test_noise_metrics.py
from app.infrastructure.analysis.chords import Chord
from app.infrastructure.analysis.noise_metrics import short_fraction, flicker_per_min

def test_short_fraction_counts_sub_threshold():
    ch = [Chord("C", 0.0, 1.0, 0.9), Chord("G", 1.0, 1.2, 0.9)]  # 0.2s short
    assert short_fraction(ch) == 0.5
    assert short_fraction([]) == 0.0

def test_flicker_counts_sandwiched_short_segment():
    # C [long] G [0.2s short] C [long] -> one flicker (G between two C)
    ch = [Chord("C", 0.0, 1.0, 0.9), Chord("G", 1.0, 1.2, 0.9), Chord("C", 1.2, 2.2, 0.9)]
    assert flicker_per_min(ch, duration=60.0) == 1.0

def test_flicker_ignores_long_sandwiched_segment():
    # G is 1s (>=0.5) -> not a flicker even though neighbors match
    ch = [Chord("C", 0.0, 1.0, 0.9), Chord("G", 1.0, 2.0, 0.9), Chord("C", 2.0, 3.0, 0.9)]
    assert flicker_per_min(ch, duration=60.0) == 0.0
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && pytest tests/analysis/test_noise_metrics.py -v`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `noise_metrics.py`**

```python
# server/app/infrastructure/analysis/noise_metrics.py
"""Ground-truth-free noise metrics over a decoded chord timeline.

short_fraction: how much of the timeline is sub-threshold junk.
flicker_per_min: A->B->A flips where B is a short segment (almost always error).
"""
from .chords import Chord


def short_fraction(chords: list[Chord], thresh: float = 0.5) -> float:
    if not chords:
        return 0.0
    short = sum(1 for c in chords if c.end - c.start < thresh)
    return short / len(chords)


def flicker_per_min(chords: list[Chord], duration: float, thresh: float = 0.5) -> float:
    if duration <= 0:
        return 0.0
    n = len(chords)
    flick = sum(
        1 for i in range(1, n - 1)
        if chords[i - 1].chord == chords[i + 1].chord
        and (chords[i].end - chords[i].start) < thresh
    )
    return flick / (duration / 60.0)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && pytest tests/analysis/test_noise_metrics.py -v`
Expected: PASS (3 passed).

- [ ] **Step 5: Commit**

```bash
git add server/app/infrastructure/analysis/noise_metrics.py server/tests/analysis/test_noise_metrics.py
git commit -m "feat(analysis): chord-timeline noise metrics (short fraction, flicker per min)"
```

---

### Task 2: Bump vote minChordDur default to 0.5 (Dart + Python parity)

**Files:**
- Modify: `server/app/infrastructure/analysis/vote_decode.py` (default `min_chord_dur=0.3` → `0.5`)
- Modify: `app/lib/core/decode/vote_decode.dart` (default `minChordDur = 0.3` → `0.5`)
- Modify: `app/test/decode/vote_decode_test.dart` (make the one default-dependent test explicit)

**Interfaces:**
- Produces: `vote_decode(frames, spec, smoothing_kernel=5, min_chord_dur=0.5)` (Python) and `voteDecode(frames, spec, {smoothingKernel=5, minChordDur=0.5})` (Dart).

- [ ] **Step 1: Update the Python default**

In `server/app/infrastructure/analysis/vote_decode.py`, change the `vote_decode` signature default from `min_chord_dur: float = 0.3` to `min_chord_dur: float = 0.5`. (No Python unit test asserts on this default — `test_vote_decode.py` calls `merge_short_chords(..., 0.3)` explicitly.)

- [ ] **Step 2: Run the Python analysis suite to confirm no regression**

Run: `cd server && pytest tests/analysis/ -q`
Expected: PASS (no test depended on the 0.3 default).

- [ ] **Step 3: Fix the one default-dependent Dart test BEFORE changing the Dart default**

In `app/test/decode/vote_decode_test.dart`, the test `'short junk segment is absorbed into the longer neighbor'` (currently uses the default `minChordDur`) relies on the C(0.46s)/G(0.46s) runs surviving at threshold 0.3. At 0.5 they'd both be absorbed into one 'C'. Preserve the test's intent (junk-absorption mechanics at a known threshold) by making the threshold explicit. Change the call:

```dart
    // Absorption mechanics tested at an explicit 0.3s threshold (independent
    // of the vote default). X spans ~0.093s -> absorbed; C(5)/G(5) tie -> C.
    final chords = voteDecode(frames, spec, smoothingKernel: 1, minChordDur: 0.3);
```

Leave the `greaterThanOrEqualTo(0.3)` invariant and `['C','G']` expectation as-is (both hold at explicit 0.3).

- [ ] **Step 4: Update the Dart default**

In `app/lib/core/decode/vote_decode.dart`, change the `voteDecode` parameter default from `double minChordDur = 0.3` to `double minChordDur = 0.5`. Update the adjacent doc comment's "0.3" reference to "0.5".

- [ ] **Step 5: Run the Dart vote-decode tests**

Run: `cd app && flutter test test/decode/vote_decode_test.dart`
Expected: PASS (all tests). If any other test fails on the new default, make its threshold explicit `minChordDur: 0.3` the same way — do not change assertions.

- [ ] **Step 6: Commit**

```bash
git add server/app/infrastructure/analysis/vote_decode.py app/lib/core/decode/vote_decode.dart app/test/decode/vote_decode_test.dart
git commit -m "fix(denoise): vote fallback minChordDur 0.3->0.5 (#5), Dart+Python parity"
```

---

### Task 3: Real-clip noise regression gate

**Files:**
- Create: `server/tests/analysis/test_denoise_gate.py`

**Interfaces:**
- Consumes: `load_spec`, `decode_pcm`, `run_pcm`, `track_beats`, `beat_sync_chords`, `vote_decode`, `short_fraction`, `flicker_per_min`.

- [ ] **Step 1: Write the gate test**

```python
# server/tests/analysis/test_denoise_gate.py
"""Regression gate: denoise stays clean on a real clip.

Decodes the first 30s of the in-repo BTC reference clip and asserts the
default beat-sync path has no flicker / no sub-0.5s junk, and the vote
fallback path (at the new 0.5 default) has no sub-0.5s junk. Skips when
btc.onnx is absent (conftest guard) or the mp3 can't be decoded.
"""
from pathlib import Path
import pytest

from app.infrastructure.analysis.manifest import load_spec
from app.infrastructure.analysis.audio_io import decode_pcm
from app.infrastructure.analysis.onnx_infer import run_pcm
from app.infrastructure.analysis.beat import track_beats
from app.infrastructure.analysis.beat_sync import beat_sync_chords
from app.infrastructure.analysis.vote_decode import vote_decode
from app.infrastructure.analysis.noise_metrics import short_fraction, flicker_per_min

CLIP = Path(__file__).resolve().parents[3] / "reference" / "BTC-ISMIR19" / "test" / "example.mp3"


def _pcm_30s(spec):
    if not CLIP.exists():
        pytest.skip(f"reference clip not found: {CLIP}")
    try:
        full = decode_pcm(str(CLIP), spec.fs)
    except Exception as e:
        pytest.skip(f"cannot decode {CLIP.name}: {e}")
    return full[: spec.fs * 30]


def test_beatsync_path_is_clean_on_real_clip():
    spec = load_spec("btc")
    pcm = _pcm_30s(spec)
    dur = len(pcm) / spec.fs
    frames = run_pcm(pcm, spec)
    br = track_beats(pcm, sr=float(spec.fs))
    assert br.beats, "expected the tracker to find beats on this clip"
    d = sorted(br.beats[i] - br.beats[i - 1] for i in range(1, len(br.beats)))
    min_dur = 1.4 * d[len(d) // 2]
    chords = beat_sync_chords(frames, br.beats, spec, min_chord_dur=min_dur)
    assert flicker_per_min(chords, dur) == 0.0
    assert short_fraction(chords) == 0.0


def test_vote_fallback_has_no_short_junk_at_default():
    spec = load_spec("btc")
    pcm = _pcm_30s(spec)
    frames = run_pcm(pcm, spec)
    chords = vote_decode(frames, spec)  # default min_chord_dur now 0.5
    assert short_fraction(chords) == 0.0
```

- [ ] **Step 2: Run the gate**

Run: `cd server && pytest tests/analysis/test_denoise_gate.py -v`
Expected: PASS (2 passed). Confirms the beat-sync path is clean and the vote default now yields no sub-0.5s segments on the real clip.

- [ ] **Step 3: Run the full server suite**

Run: `cd server && pytest tests/ -q`
Expected: PASS (all; onnx-dependent tests run since btc.onnx is present, or skip on a clean checkout).

- [ ] **Step 4: Commit**

```bash
git add server/tests/analysis/test_denoise_gate.py
git commit -m "test(denoise): real-clip regression gate (beat-sync clean, vote no sub-0.5s junk)"
```

---

## Self-Review

- **Spec coverage:** noise metrics (Task 1), vote knob 0.3→0.5 parity + Dart test fix (Task 2), real-clip gate with beat-sync 0/0 and vote short=0 + onnx/decoder skip (Task 3). Spec's "no algorithm change / no similar-alternation / no UI" respected. All covered.
- **Placeholder scan:** none — all steps carry real code and exact commands.
- **Type consistency:** `short_fraction(chords, thresh=0.5)`, `flicker_per_min(chords, duration, thresh=0.5)`, `vote_decode(..., min_chord_dur=0.5)` / `voteDecode(..., minChordDur=0.5)` used consistently across Tasks 1–3.
```
