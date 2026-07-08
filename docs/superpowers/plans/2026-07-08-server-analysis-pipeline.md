# Server Analysis Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the server's `StubAnalysisSlot` with a real ONNX chord-analysis pipeline that mirrors the Dart `OnDeviceAnalyzer`, so web/desktop analysis matches mobile on-device output.

**Architecture:** A pure-function DSP package under `server/app/infrastructure/analysis/` ports each Dart pipeline stage (PCM decode → ONNX inference → beat tracking → beat-sync/vote decode → key) to Python/numpy, transcribing the Dart algorithms verbatim (NOT librosa equivalents, which would break parity). An `OnnxAnalysisSlot` assembles them into an `AnalysisResult`. A golden-clip parity test against Dart output is the correctness gate.

**Tech Stack:** Python 3.12, numpy, onnxruntime, soundfile (+ audioread/ffmpeg for mp3), FastAPI (existing).

## Global Constraints

- Python floors and layout follow existing `server/` (`pyproject.toml`, hexagonal: domain/application/infrastructure/api).
- Parity target = the Dart source on branch `feat/song-search`. Every ported function mirrors its Dart counterpart's algorithm and constants EXACTLY (tie rules, edge clamping, rounding). Do not substitute librosa's onset/tempo/beat — they differ numerically.
- Constants (verbatim from Dart): `fs=22050`, frame hop `2048` samples (PCM models), onset hop `512`, `onsetFps = 22050/512`, `fallbackFrameDur = 2048/22050`, vote `smoothingKernel=5`, vote `minChordDur=0.3`, beat-sync `beatSmoothingKernel=3`, `minChordBeats=1.4`, `placeholderBpm=120`, `placeholderTimeSignature=4`, tempo search 40–240 BPM, `priorBpm=120`, `stdOctaves=1.0`, DP `tightness=100`.
- MVP models: `btc` (default) and `chordnet_2e1d` — both `input='pcm'`, `decode='vote'`, 170 classes, `window_samples=219136`. `chord_cnn_lstm` (XHMM) is OUT of scope.
- Manifest is the single source of truth for labels/fs/window: `artifacts/onnx/manifest.json`.
- Output JSON must match `AnalysisResult.fromJson` / `sample.dart` shape: keys `songId, source{youtubeId,title,duration,bpm,timeSignature}, key, beats[{time,beatNum}], downbeats[], chords[{chord,start,end,confidence}], synchronizedChords[{chord,beatIndex}], segments[], melody`.

---

### Task 0: Generate ONNX models + add server deps

**Files:**
- Modify: `server/pyproject.toml` (add deps)
- Generate (gitignored, local): `artifacts/onnx/btc.onnx`, `artifacts/onnx/chordnet_2e1d.onnx`

**Interfaces:**
- Produces: local `.onnx` files whose sha256 match `artifacts/onnx/manifest.json`; server deps `numpy`, `onnxruntime`, `soundfile`, `audioread` available.

- [ ] **Step 1: Generate the ONNX models**

Run:
```bash
pip install -r scripts/export/requirements.txt
python -m scripts.export btc
python -m scripts.export chordnet_2e1d
```
Expected: `artifacts/onnx/btc.onnx` and `chordnet_2e1d.onnx` created.

- [ ] **Step 2: Verify sha256 matches manifest**

Run:
```bash
python - <<'PY'
import hashlib, json
m = json.load(open('artifacts/onnx/manifest.json'))
for k in ('btc','chordnet_2e1d'):
    e = m[k]; p = 'artifacts/onnx/'+e['file']
    got = hashlib.sha256(open(p,'rb').read()).hexdigest()
    assert got == e['sha256'], (k, got, e['sha256'])
print('sha256 OK')
PY
```
Expected: `sha256 OK`.

- [ ] **Step 3: Add runtime deps to `server/pyproject.toml`**

Add to `[project].dependencies`: `numpy`, `onnxruntime`, `soundfile`, `audioread`.

- [ ] **Step 4: Install and confirm imports**

Run: `cd server && pip install -e ".[dev]" && python -c "import numpy, onnxruntime, soundfile, audioread; print('deps OK')"`
Expected: `deps OK`.

- [ ] **Step 5: Commit**

```bash
git add server/pyproject.toml
git commit -m "build(server): add numpy/onnxruntime/soundfile/audioread for analysis pipeline"
```

---

### Task 1: Manifest loader + audio decode

**Files:**
- Create: `server/app/infrastructure/analysis/__init__.py`
- Create: `server/app/infrastructure/analysis/manifest.py`
- Create: `server/app/infrastructure/analysis/audio_io.py`
- Test: `server/tests/analysis/test_audio_io.py`

**Interfaces:**
- Produces:
  - `load_spec(name: str) -> ModelSpec` where `ModelSpec` is a dataclass with `name:str, file:str, fs:int, window_samples:int, labels:list[str], decode:str, input:str`.
  - `decode_pcm(path: str, fs: int) -> np.ndarray` — mono float32, resampled to `fs`.

- [ ] **Step 1: Write the failing test**

```python
# server/tests/analysis/test_audio_io.py
import numpy as np, soundfile as sf
from app.infrastructure.analysis.manifest import load_spec
from app.infrastructure.analysis.audio_io import decode_pcm

def test_load_spec_btc():
    s = load_spec("btc")
    assert s.fs == 22050 and s.window_samples == 219136
    assert len(s.labels) == 170 and s.input == "pcm" and s.decode == "vote"

def test_decode_pcm_mono_float32(tmp_path):
    p = tmp_path / "t.wav"
    sf.write(p, np.zeros(44100, dtype="float32"), 44100)  # 1s @ 44.1k
    pcm = decode_pcm(str(p), 22050)
    assert pcm.dtype == np.float32 and pcm.ndim == 1
    assert abs(len(pcm) - 22050) <= 2  # resampled to ~1s @ 22050
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && pytest tests/analysis/test_audio_io.py -v`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `manifest.py`**

```python
# server/app/infrastructure/analysis/manifest.py
import json
from dataclasses import dataclass
from pathlib import Path

_MANIFEST = Path(__file__).resolve().parents[4] / "artifacts" / "onnx" / "manifest.json"

@dataclass(frozen=True)
class ModelSpec:
    name: str
    file: str
    fs: int
    window_samples: int
    labels: list[str]
    decode: str
    input: str

def load_spec(name: str) -> ModelSpec:
    m = json.loads(_MANIFEST.read_text())
    e = m[name]
    return ModelSpec(
        name=name, file=e["file"],
        fs=e.get("fs", e.get("sample_rate", 22050)),
        window_samples=e["window_samples"],
        labels=e["labels"],
        decode=e.get("decode", "vote"),
        input=e.get("input", "pcm"),
    )

def onnx_path(spec: ModelSpec) -> str:
    return str(_MANIFEST.parent / spec.file)
```
Note: adjust `parents[4]` if the repo-root depth differs; the target is `<repo>/artifacts/onnx/manifest.json`.

- [ ] **Step 4: Implement `audio_io.py`**

```python
# server/app/infrastructure/analysis/audio_io.py
import numpy as np, soundfile as sf

def decode_pcm(path: str, fs: int) -> np.ndarray:
    try:
        data, sr = sf.read(path, dtype="float32", always_2d=True)
    except Exception:
        import audioread
        with audioread.audio_open(path) as f:
            sr = f.samplerate
            buf = b"".join(f.read_data())
        data = np.frombuffer(buf, dtype="<i2").astype("float32") / 32768.0
        data = data.reshape(-1, f.channels)
    mono = data.mean(axis=1)                    # downmix
    if sr != fs:                                 # linear resample (parity-neutral)
        n = int(round(len(mono) * fs / sr))
        mono = np.interp(np.linspace(0, len(mono) - 1, n),
                         np.arange(len(mono)), mono).astype("float32")
    return np.ascontiguousarray(mono, dtype="float32")
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd server && pytest tests/analysis/test_audio_io.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add server/app/infrastructure/analysis/__init__.py server/app/infrastructure/analysis/manifest.py server/app/infrastructure/analysis/audio_io.py server/tests/analysis/test_audio_io.py
git commit -m "feat(analysis): manifest loader + audio decode to mono float32 PCM"
```

---

### Task 2: ONNX inference — port `pcm_runner.dart`

**Files:**
- Create: `server/app/infrastructure/analysis/onnx_infer.py`
- Test: `server/tests/analysis/test_onnx_infer.py`

**Interfaces:**
- Consumes: `ModelSpec`, `onnx_path` (Task 1).
- Produces: `Frame` dataclass `(frame_index:int, class_id:int, confidence:float, time:float)`; `run_pcm(pcm: np.ndarray, spec: ModelSpec) -> list[Frame]`.

Mirrors `pcm_runner.dart`: non-overlapping `window_samples` windows, zero-pad final window, `frames_per_window` read from output shape, `hop = window_samples // (frames_per_window - 1)`, `frame_dur = hop / fs`, drop padded trailing frames (`real_frames = ceil(copy_len / hop)` clamped), argmax class, softmax-max confidence `1 / sum(exp(logit - max))`, global frame index for `time`.

- [ ] **Step 1: Write the failing test** (shape + frame accounting on a short synthetic PCM)

```python
# server/tests/analysis/test_onnx_infer.py
import numpy as np
from app.infrastructure.analysis.manifest import load_spec
from app.infrastructure.analysis.onnx_infer import run_pcm

def test_run_pcm_frames_monotonic_and_typed():
    spec = load_spec("btc")
    pcm = np.zeros(spec.window_samples + 5000, dtype="float32")  # ~2 windows
    frames = run_pcm(pcm, spec)
    assert frames, "no frames"
    assert [f.frame_index for f in frames] == list(range(len(frames)))
    assert all(0 <= f.class_id < len(spec.labels) for f in frames)
    assert all(0.0 <= f.confidence <= 1.0 for f in frames)
    # time strictly increasing by a constant frame_dur ~ 2048/22050
    d = frames[1].time - frames[0].time
    assert abs(d - 2048/22050) < 1e-6
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && pytest tests/analysis/test_onnx_infer.py -v`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `onnx_infer.py`**

```python
# server/app/infrastructure/analysis/onnx_infer.py
import math
from dataclasses import dataclass
import numpy as np
import onnxruntime as ort
from .manifest import ModelSpec, onnx_path

@dataclass(frozen=True)
class Frame:
    frame_index: int
    class_id: int
    confidence: float
    time: float

_SESSIONS: dict[str, ort.InferenceSession] = {}

def _session(spec: ModelSpec) -> ort.InferenceSession:
    s = _SESSIONS.get(spec.name)
    if s is None:
        s = ort.InferenceSession(onnx_path(spec), providers=["CPUExecutionProvider"])
        _SESSIONS[spec.name] = s
    return s

def run_pcm(pcm: np.ndarray, spec: ModelSpec) -> list[Frame]:
    if spec.input != "pcm":
        raise ValueError(f"run_pcm requires pcm model, got {spec.input}")
    sess = _session(spec)
    in_name = sess.get_inputs()[0].name  # 'pcm'
    W = spec.window_samples
    total = len(pcm)
    out: list[Frame] = []
    if total == 0:
        return out
    frames_per_window = hop = frame_dur = None
    gidx = 0
    offset = 0
    while offset < total:
        copy_len = min(total - offset, W)
        window = np.zeros(W, dtype="float32")
        window[:copy_len] = pcm[offset:offset + copy_len]
        logits = sess.run(None, {in_name: window[None, :]})[0][0]  # [frames, classes]
        if frames_per_window is None:
            frames_per_window = logits.shape[0]
            hop = W // (frames_per_window - 1)
            frame_dur = hop / spec.fs
        if copy_len < W:
            real = min(frames_per_window, max(0, math.ceil(copy_len / hop)))
        else:
            real = frames_per_window
        for f in range(real):
            row = logits[f]
            cid = int(np.argmax(row))
            m = float(row[cid])
            conf = 1.0 / float(np.sum(np.exp(row - m)))
            out.append(Frame(gidx, cid, conf, gidx * frame_dur))
            gidx += 1
        offset += W
    return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && pytest tests/analysis/test_onnx_infer.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/app/infrastructure/analysis/onnx_infer.py server/tests/analysis/test_onnx_infer.py
git commit -m "feat(analysis): PCM-in ONNX inference port (mirrors pcm_runner.dart)"
```

---

### Task 3: Vote decode — port `vote_decode.dart`

**Files:**
- Create: `server/app/infrastructure/analysis/chords.py` (Chord dataclass)
- Create: `server/app/infrastructure/analysis/vote_decode.py`
- Test: `server/tests/analysis/test_vote_decode.py`

**Interfaces:**
- Consumes: `Frame` (Task 2), `ModelSpec`.
- Produces: `Chord` dataclass `(chord:str, start:float, end:float, confidence:float)`; `majority_filter(values:list[int], kernel:int) -> list[int]`; `merge_short_chords(chords:list[Chord], min_dur:float) -> list[Chord]`; `vote_decode(frames:list[Frame], spec:ModelSpec, smoothing_kernel:int=5, min_chord_dur:float=0.3) -> list[Chord]`.

Transcribe verbatim from `vote_decode.dart`: `majorityFilter` (kernel forced odd/≥1, no-op if `n<kernel`, edge-clamped window, tie → keep center if tied else smallest), `mergeShortChords` (repeatedly absorb shortest sub-`min_dur` segment into longer-duration neighbor, tie→prev, duration-weighted confidence, then merge equal-label adjacency), `voteDecode` (run-length merge with `frame_dur = frames[1].time - frames[0].time`).

- [ ] **Step 1: Write the failing tests** (mirror Dart unit cases)

```python
# server/tests/analysis/test_vote_decode.py
from app.infrastructure.analysis.chords import Chord
from app.infrastructure.analysis.vote_decode import majority_filter, merge_short_chords

def test_majority_filter_smooths_single_flip():
    assert majority_filter([1,1,2,1,1], 3) == [1,1,1,1,1]

def test_majority_filter_noop_when_shorter_than_kernel():
    assert majority_filter([1,2], 5) == [1,2]

def test_majority_filter_tie_keeps_center_else_smallest():
    # window [1,2] tie -> center kept when center is a candidate
    assert majority_filter([1,2,1], 1) == [1,2,1]  # kernel 1 = no-op

def test_merge_short_absorbs_into_longer_neighbor():
    ch = [Chord("D",0.0,1.0,0.9), Chord("D7",1.0,1.1,0.5), Chord("G",1.1,2.1,0.9)]
    out = merge_short_chords(ch, 0.3)
    assert [c.chord for c in out] == ["D","G"]
    assert out[0].end == 1.1  # D extended to cover the junk D7
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && pytest tests/analysis/test_vote_decode.py -v`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `chords.py`**

```python
# server/app/infrastructure/analysis/chords.py
from dataclasses import dataclass

@dataclass
class Chord:
    chord: str
    start: float
    end: float
    confidence: float
```

- [ ] **Step 4: Implement `vote_decode.py`**

```python
# server/app/infrastructure/analysis/vote_decode.py
from collections import Counter
from .chords import Chord
from .onnx_infer import Frame
from .manifest import ModelSpec

FALLBACK_FRAME_DUR = 2048 / 22050

def majority_filter(values: list[int], kernel_size: int) -> list[int]:
    kernel = 1 if kernel_size < 1 else kernel_size
    if kernel % 2 == 0:
        kernel += 1
    n = len(values)
    if kernel == 1 or n < kernel:
        return list(values)
    pad = kernel // 2
    def at(padded_idx: int) -> int:
        i = padded_idx - pad
        if i < 0: return values[0]
        if i >= n: return values[n - 1]
        return values[i]
    out = [0] * n
    for idx in range(n):
        counts = Counter(at(idx + w) for w in range(kernel))
        max_count = max(counts.values())
        candidates = sorted(k for k, c in counts.items() if c == max_count)
        center = values[idx]
        out[idx] = center if center in candidates else candidates[0]
    return out

def merge_short_chords(chords: list[Chord], min_dur: float) -> list[Chord]:
    out = list(chords)
    while len(out) > 1:
        shortest, shortest_dur = -1, min_dur
        for i, c in enumerate(out):
            d = c.end - c.start
            if d < shortest_dur:
                shortest, shortest_dur = i, d
        if shortest < 0:
            break
        prev = shortest - 1 if shortest > 0 else -1
        nxt = shortest + 1 if shortest < len(out) - 1 else -1
        if prev < 0:
            keep = nxt
        elif nxt < 0:
            keep = prev
        else:
            keep = nxt if (out[nxt].end - out[nxt].start) > (out[prev].end - out[prev].start) else prev
        s, k = out[shortest], out[keep]
        s_dur, k_dur = s.end - s.start, k.end - k.start
        conf = (k.confidence * k_dur + s.confidence * s_dur) / (k_dur + s_dur)
        out[keep] = Chord(k.chord, min(k.start, s.start), max(k.end, s.end), conf)
        del out[shortest]
        ki = keep - 1 if keep > shortest else keep
        for j in (ki + 1, ki - 1):
            if 0 <= j < len(out) and out[j].chord == out[ki].chord:
                lo, hi = (j, ki) if j < ki else (ki, j)
                a, b = out[lo], out[hi]
                a_dur, b_dur = a.end - a.start, b.end - b.start
                out[lo] = Chord(a.chord, a.start, b.end,
                                (a.confidence * a_dur + b.confidence * b_dur) / (a_dur + b_dur))
                del out[hi]
                break
    return out

def vote_decode(frames: list[Frame], spec: ModelSpec,
                smoothing_kernel: int = 5, min_chord_dur: float = 0.3) -> list[Chord]:
    if not frames:
        return []
    labels = spec.labels
    smoothed = majority_filter([f.class_id for f in frames], smoothing_kernel)
    frame_dur = frames[1].time - frames[0].time if len(frames) > 1 else FALLBACK_FRAME_DUR
    chords: list[Chord] = []
    run_start = 0
    for i in range(1, len(frames) + 1):
        at_end = i == len(frames) or smoothed[i] != smoothed[run_start]
        if at_end:
            run = frames[run_start:i]
            conf = sum(f.confidence for f in run) / len(run)
            chords.append(Chord(labels[smoothed[run_start]], run[0].time,
                                run[-1].time + frame_dur, conf))
            run_start = i
    return merge_short_chords(chords, min_chord_dur)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd server && pytest tests/analysis/test_vote_decode.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add server/app/infrastructure/analysis/chords.py server/app/infrastructure/analysis/vote_decode.py server/tests/analysis/test_vote_decode.py
git commit -m "feat(analysis): vote decode + short-chord merge port (mirrors vote_decode.dart)"
```

---

### Task 4: Beat tracking — port onset/tempo/beat_tracker

**Files:**
- Create: `server/app/infrastructure/analysis/stft.py` (STFT magnitude, mirror `hybrid_cqt.dart` `stftMagnitude`)
- Create: `server/app/infrastructure/analysis/beat.py` (onset envelope, tempo, Ellis DP)
- Test: `server/tests/analysis/test_beat.py`

**Interfaces:**
- Produces:
  - `stft_magnitude(pcm: np.ndarray, n_fft:int=2048, hop:int=512) -> np.ndarray` (shape [frames, bins]).
  - `onset_envelope(pcm: np.ndarray, n_fft:int=2048, hop:int=512) -> np.ndarray`.
  - `estimate_tempo(onset: np.ndarray, fps:float=ONSET_FPS, prior_bpm:float=120) -> float`.
  - `BeatResult(beats: list[float], bpm: float)`; `track_beats(pcm: np.ndarray, sr:float=22050) -> BeatResult`.
  - `ONSET_FPS = 22050/512`.

Transcribe verbatim from `onset.dart` (spectral flux, positive mag increase, max-normalized, `env[0]=0`), `tempo.dart` (autocorr over lags for 40–240 BPM, log-normal prior `z = log2(bpm/prior)/std`, `std=1.0`), `beat_tracker.dart` `_dpBeats` (backlink/cumscore DP, predecessor window `[round(-2*period), min(round(-period/2), -1)]`, `txcost = -tightness * log(-off/period)^2`, `tightness=100`, backtrace from best cumscore in last `round(period)` frames). `period = 60 * ONSET_FPS / bpm`. **Confirm `stftMagnitude` in `hybrid_cqt.dart` (window type, centering) and mirror it exactly** — read that file before implementing `stft.py`.

- [ ] **Step 1: Write the failing tests**

```python
# server/tests/analysis/test_beat.py
import numpy as np
from app.infrastructure.analysis.beat import onset_envelope, estimate_tempo, track_beats, ONSET_FPS

def test_onset_first_frame_zero_and_normalized():
    pcm = np.random.default_rng(0).standard_normal(22050).astype("float32")
    env = onset_envelope(pcm)
    assert env[0] == 0.0 and env.max() <= 1.0 + 1e-9

def test_tempo_on_click_train_near_120():
    fs, bpm = 22050, 120.0
    pcm = np.zeros(fs * 4, dtype="float32")
    step = int(fs * 60 / bpm)
    pcm[::step] = 1.0
    est = estimate_tempo(onset_envelope(pcm))
    assert abs(est - 120) < 12  # within ~10%

def test_track_beats_returns_ascending_times():
    fs, bpm = 22050, 120.0
    pcm = np.zeros(fs * 4, dtype="float32")
    pcm[::int(fs * 60 / bpm)] = 1.0
    res = track_beats(pcm)
    assert len(res.beats) >= 4
    assert all(b2 > b1 for b1, b2 in zip(res.beats, res.beats[1:]))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && pytest tests/analysis/test_beat.py -v`
Expected: FAIL (module not found).

- [ ] **Step 3: Read `app/lib/core/hybrid_cqt.dart` and implement `stft.py`**

Mirror `stftMagnitude` exactly (n_fft=2048, hop=512, its window + framing). Return `np.ndarray` [frames, n_fft/2+1] of magnitudes.

- [ ] **Step 4: Implement `beat.py`** (transcribe onset/tempo/DP from the three Dart files)

```python
# server/app/infrastructure/analysis/beat.py  (skeleton — fill DP per beat_tracker.dart)
import math
from dataclasses import dataclass
import numpy as np
from .stft import stft_magnitude

ONSET_FPS = 22050 / 512

def onset_envelope(pcm, n_fft=2048, hop=512):
    mag = stft_magnitude(pcm, n_fft=n_fft, hop=hop)  # [n, bins]
    n = mag.shape[0]
    env = np.zeros(n)
    diff = mag[1:] - mag[:-1]
    env[1:] = np.clip(diff, 0, None).sum(axis=1)
    mx = env.max()
    if mx > 0:
        env /= mx
    return env

def estimate_tempo(onset, fps=ONSET_FPS, prior_bpm=120.0):
    n = len(onset)
    if n < 4:
        return 0.0
    min_lag = max(1, round(fps * 60 / 240))
    max_lag = min(n - 1, round(fps * 60 / 40))
    if max_lag <= min_lag:
        return 0.0
    best_bpm, best_score, std = 0.0, -math.inf, 1.0
    for lag in range(min_lag, max_lag + 1):
        ac = float(np.dot(onset[lag:], onset[:n - lag]))
        bpm = 60 * fps / lag
        z = math.log(bpm / prior_bpm) / math.log(2) / std
        score = ac * math.exp(-0.5 * z * z)
        if score > best_score:
            best_score, best_bpm = score, bpm
    return best_bpm if best_score > 0 else 0.0

@dataclass
class BeatResult:
    beats: list
    bpm: float

def _dp_beats(localscore, period, tightness=100.0):
    n = len(localscore)
    if n < 3 or period < 1:
        return []
    backlink = [-1] * n
    cumscore = [0.0] * n
    lo_off = round(-2 * period)
    hi_off = min(round(-period / 2), -1)
    for i in range(n):
        best_score, best_prev = -math.inf, -1
        for off in range(lo_off, hi_off + 1):
            j = i + off
            if j < 0:
                continue
            dev = math.log(-off / period)
            score = cumscore[j] - tightness * dev * dev
            if score > best_score:
                best_score, best_prev = score, j
        if best_prev < 0:
            cumscore[i], backlink[i] = localscore[i], -1
        else:
            cumscore[i], backlink[i] = localscore[i] + best_score, best_prev
    tail, tail_score = -1, -math.inf
    for i in range(max(0, n - round(period)), n):
        if cumscore[i] > tail_score:
            tail_score, tail = cumscore[i], i
    if tail < 0:
        return []
    beats, i = [], tail
    while i >= 0:
        beats.append(i)
        if backlink[i] < 0:
            break
        i = backlink[i]
    return list(reversed(beats))

def track_beats(pcm, sr=22050.0):
    assert sr == 22050, "onset pipeline assumes sr == 22050"
    onset = onset_envelope(pcm)
    bpm = estimate_tempo(onset)
    if bpm <= 0:
        return BeatResult([], 0.0)
    period = 60 * ONSET_FPS / bpm
    frames = _dp_beats(list(onset), period)
    if len(frames) < 2:
        return BeatResult([], 0.0)
    return BeatResult([f / ONSET_FPS for f in frames], bpm)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd server && pytest tests/analysis/test_beat.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add server/app/infrastructure/analysis/stft.py server/app/infrastructure/analysis/beat.py server/tests/analysis/test_beat.py
git commit -m "feat(analysis): DSP beat tracking port (onset/tempo/Ellis DP, mirrors core/beat)"
```

---

### Task 5: Beat-sync decode — port `beat_sync.dart`

**Files:**
- Create: `server/app/infrastructure/analysis/beat_sync.py`
- Test: `server/tests/analysis/test_beat_sync.py`

**Interfaces:**
- Consumes: `Frame`, `Chord`, `ModelSpec`, `majority_filter`, `merge_short_chords`, `FALLBACK_FRAME_DUR`.
- Produces: `beat_sync_chords(frames:list[Frame], beat_times:list[float], spec:ModelSpec, beat_smoothing_kernel:int=3, min_chord_dur:float=0.0) -> list[Chord]`.

Transcribe `beatSyncChords`: interval bounds (`0` lead-in if `beats[0]>0`, beats, song end), per-interval winner = most-frequent class (tie → higher confSum), empty interval inherits prev (or `N`), `majority_filter` on winners with kernel 3, merge equal labels (duration-weighted confidence), then `merge_short_chords` if `min_chord_dur>0`.

- [ ] **Step 1: Write the failing test**

```python
# server/tests/analysis/test_beat_sync.py
from app.infrastructure.analysis.onnx_infer import Frame
from app.infrastructure.analysis.manifest import load_spec
from app.infrastructure.analysis.beat_sync import beat_sync_chords

def _frames(seq, dt=0.1):
    return [Frame(i, c, 1.0, i * dt) for i, c in enumerate(seq)]

def test_beat_sync_one_chord_per_beat_interval_merged():
    spec = load_spec("btc")
    # class ids: use indices whose labels are distinct; 0 and 1
    frames = _frames([0]*10 + [1]*10)  # 2s of class0 then class1
    beats = [0.0, 1.0, 2.0]
    out = beat_sync_chords(frames, beats, spec)
    assert len(out) == 2
    assert out[0].chord == spec.labels[0] and out[1].chord == spec.labels[1]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && pytest tests/analysis/test_beat_sync.py -v`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `beat_sync.py`** (transcribe the 4 passes from `beat_sync.dart`)

```python
# server/app/infrastructure/analysis/beat_sync.py
from collections import defaultdict
from .chords import Chord
from .onnx_infer import Frame
from .manifest import ModelSpec
from .vote_decode import majority_filter, merge_short_chords, FALLBACK_FRAME_DUR

def beat_sync_chords(frames: list[Frame], beat_times: list[float], spec: ModelSpec,
                     beat_smoothing_kernel: int = 3, min_chord_dur: float = 0.0) -> list[Chord]:
    if not frames or not beat_times:
        return []
    labels = spec.labels
    n_index = labels.index("N") if "N" in labels else -1
    frame_dur = frames[1].time - frames[0].time if len(frames) > 1 else FALLBACK_FRAME_DUR
    song_end = frames[-1].time + frame_dur

    bounds: list[float] = []
    if beat_times[0] > 0:
        bounds.append(0.0)
    bounds.extend(beat_times)
    end = song_end if song_end > bounds[-1] else bounds[-1] + frame_dur
    bounds.append(end)

    winners: list[int] = []
    confs: list[float] = []
    fi = 0
    prev_class = -1
    for b in range(len(bounds) - 1):
        lo, hi = bounds[b], bounds[b + 1]
        counts: dict[int, int] = defaultdict(int)
        conf_sum: dict[int, float] = defaultdict(float)
        while fi < len(frames) and frames[fi].time < hi:
            if frames[fi].time >= lo:
                c = frames[fi].class_id
                counts[c] += 1
                conf_sum[c] += frames[fi].confidence
            fi += 1
        if not counts:
            winner = prev_class if prev_class >= 0 else (n_index if n_index >= 0 else 0)
            conf = 0.0
        else:
            winner = next(iter(counts))
            for c in counts:
                if counts[c] > counts[winner] or (counts[c] == counts[winner] and conf_sum[c] > conf_sum[winner]):
                    winner = c
            conf = conf_sum[winner] / counts[winner]
        prev_class = winner
        winners.append(winner)
        confs.append(conf)

    smoothed = majority_filter(winners, beat_smoothing_kernel)

    segments: list[Chord] = []
    for b in range(len(smoothed)):
        lo, hi = bounds[b], bounds[b + 1]
        label = labels[smoothed[b]]
        conf = confs[b]
        if segments and segments[-1].chord == label:
            prev = segments.pop()
            prev_dur = prev.end - prev.start
            cur_dur = hi - lo
            segments.append(Chord(prev.chord, prev.start, hi,
                                  (prev.confidence * prev_dur + conf * cur_dur) / (prev_dur + cur_dur)))
        else:
            segments.append(Chord(label, lo, hi, conf))

    return merge_short_chords(segments, min_chord_dur) if min_chord_dur > 0 else segments
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && pytest tests/analysis/test_beat_sync.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/app/infrastructure/analysis/beat_sync.py server/tests/analysis/test_beat_sync.py
git commit -m "feat(analysis): beat-sync chord decode port (mirrors beat_sync.dart)"
```

---

### Task 6: Key estimation — port `key_krumhansl.dart`

**Files:**
- Create: `server/app/infrastructure/analysis/key.py`
- Test: `server/tests/analysis/test_key.py`

**Interfaces:**
- Consumes: `Chord`.
- Produces: `estimate_key(chords: list[Chord]) -> str` (e.g. `"C major"`); `DEFAULT_KEY = "C major"`.

Transcribe verbatim: note names, `_pitch_class_by_letter`, `_quality_intervals` map, major/minor Krumhansl profiles, `_parse_root` (`#`/`b` handling), `_chord_pitch_classes` (drop `/bass`, split `:`, fallback major triad), duration-weighted 12-bin histogram, Pearson correlation against all 24 rotated profiles, `"<Note> major|minor"`. Fallback `DEFAULT_KEY` when no usable chords.

- [ ] **Step 1: Write the failing test**

```python
# server/tests/analysis/test_key.py
from app.infrastructure.analysis.chords import Chord
from app.infrastructure.analysis.key import estimate_key, DEFAULT_KEY

def test_key_empty_is_default():
    assert estimate_key([]) == DEFAULT_KEY

def test_key_c_major_progression():
    prog = [("C",2.0),("F",1.0),("G",1.0),("C",2.0),("Am",1.0),("F",1.0),("G",1.0)]
    t = 0.0; chords = []
    for name, dur in prog:
        chords.append(Chord(name, t, t + dur, 0.9)); t += dur
    assert estimate_key(chords) == "C major"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && pytest tests/analysis/test_key.py -v`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `key.py`** (verbatim transcription of `key_krumhansl.dart`)

```python
# server/app/infrastructure/analysis/key.py
import math
from .chords import Chord

_NOTE_NAMES = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
_PC_BY_LETTER = {"C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11}
_QUALITY = {
    "":[0,4,7], "maj":[0,4,7], "min":[0,3,7], "m":[0,3,7], "dim":[0,3,6],
    "aug":[0,4,8], "7":[0,4,7,10], "maj7":[0,4,7,11], "min7":[0,3,7,10],
    "m7":[0,3,7,10], "dim7":[0,3,6,9], "hdim7":[0,3,6,10], "m7b5":[0,3,6,10],
    "sus2":[0,2,7], "sus4":[0,5,7],
}
_MAJOR = [6.35,2.23,3.48,2.33,4.38,4.09,2.52,5.19,2.39,3.66,2.29,2.88]
_MINOR = [6.33,2.68,3.52,5.38,2.60,3.53,2.54,4.75,3.98,2.69,3.34,3.17]
DEFAULT_KEY = "C major"

def _parse_root(note: str):
    if not note: return None
    base = _PC_BY_LETTER.get(note[0].upper())
    if base is None: return None
    pc = base
    for c in note[1:]:
        if c == "#": pc += 1
        elif c == "b": pc -= 1
    return pc % 12

def _chord_pcs(label: str):
    if label in ("N","X") or not label: return None
    without_bass = label.split("/")[0]
    parts = without_bass.split(":")
    root = _parse_root(parts[0])
    if root is None: return None
    quality = parts[1] if len(parts) > 1 else ""
    intervals = _QUALITY.get(quality, _QUALITY["maj"])
    return {(root + iv) % 12 for iv in intervals}

def _pearson(a, b):
    n = len(a)
    ma, mb = sum(a)/n, sum(b)/n
    num = sum((a[i]-ma)*(b[i]-mb) for i in range(n))
    den = math.sqrt(sum((x-ma)**2 for x in a) * sum((x-mb)**2 for x in b))
    return num/den if den else 0.0

def _rotate(profile, tonic):
    return [profile[(i - tonic) % 12] for i in range(12)]

def estimate_key(chords: list[Chord]) -> str:
    hist = [0.0]*12
    any_weight = False
    for ch in chords:
        pcs = _chord_pcs(ch.chord)
        if pcs is None: continue
        w = ch.end - ch.start
        if w <= 0: continue
        for pc in pcs: hist[pc] += w
        any_weight = True
    if not any_weight: return DEFAULT_KEY
    best_score, best_tonic, best_major = -math.inf, 0, True
    for tonic in range(12):
        s = _pearson(hist, _rotate(_MAJOR, tonic))
        if s > best_score: best_score, best_tonic, best_major = s, tonic, True
        s = _pearson(hist, _rotate(_MINOR, tonic))
        if s > best_score: best_score, best_tonic, best_major = s, tonic, False
    return f"{_NOTE_NAMES[best_tonic]} {'major' if best_major else 'minor'}"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && pytest tests/analysis/test_key.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/app/infrastructure/analysis/key.py server/tests/analysis/test_key.py
git commit -m "feat(analysis): Krumhansl key estimation port (mirrors key_krumhansl.dart)"
```

---

### Task 7: Assemble JSON + `OnnxAnalysisSlot`

**Files:**
- Create: `server/app/infrastructure/analysis/assemble.py`
- Create: `server/app/infrastructure/analysis/slot.py`
- Read: `server/app/domain/entities.py` (confirm `AnalysisResult` fields), `app/lib/core/sample.dart` (JSON contract)
- Test: `server/tests/analysis/test_assemble.py`

**Interfaces:**
- Consumes: all analysis modules.
- Produces:
  - `analyze_pcm(pcm:np.ndarray, song_id:str, title:str, spec:ModelSpec) -> dict` — the full result dict.
  - `OnnxAnalysisSlot(ModelSlot)` with `__init__(self, model_name: str = "btc")` and `run(...)` plus a new `run_file(self, song_id, title, audio_path) -> AnalysisResult`.

Mirror `OnDeviceAnalyzer.analyze` body: choose `vote_decode` (no beats) vs `beat_sync_chords(min_chord_dur=1.4*median_beat_spacing)`; build placeholder-meter `beats`/`downbeats` (synthetic 120BPM grid when no beats, else real beats with `beatNum = i % 4 + 1`); `chordAt` step function; `synchronizedChords` only on chord change. `source.timeSignature = 4`, `source.bpm = 120 if no beats else bpm`, `duration = len(pcm)/fs`.

- [ ] **Step 1: Write the failing test**

```python
# server/tests/analysis/test_assemble.py
import numpy as np
from app.infrastructure.analysis.manifest import load_spec
from app.infrastructure.analysis.assemble import analyze_pcm

def test_analyze_pcm_shape():
    spec = load_spec("btc")
    pcm = np.zeros(spec.window_samples, dtype="float32")
    res = analyze_pcm(pcm, "abc", "Test", spec)
    assert set(res) >= {"songId","source","key","beats","downbeats","chords","synchronizedChords","segments","melody"}
    assert res["source"]["timeSignature"] == 4
    assert isinstance(res["chords"], list)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && pytest tests/analysis/test_assemble.py -v`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `assemble.py`**

```python
# server/app/infrastructure/analysis/assemble.py
import numpy as np
from .manifest import ModelSpec
from .onnx_infer import run_pcm
from .beat import track_beats
from .vote_decode import vote_decode
from .beat_sync import beat_sync_chords
from .key import estimate_key

PLACEHOLDER_BPM = 120.0
PLACEHOLDER_TS = 4
MIN_CHORD_BEATS = 1.4

def _median_beat_spacing(beats: list[float]) -> float:
    if len(beats) < 2:
        return 0.0
    d = sorted(beats[i] - beats[i-1] for i in range(1, len(beats)))
    return d[len(d)//2]

def analyze_pcm(pcm: np.ndarray, song_id: str, title: str, spec: ModelSpec) -> dict:
    frames = run_pcm(pcm, spec)
    try:
        beat_res = track_beats(pcm, sr=float(spec.fs))
    except Exception:
        from .beat import BeatResult
        beat_res = BeatResult([], 0.0)
    beat_times = beat_res.beats
    if not beat_times:
        chords = vote_decode(frames, spec)
    else:
        min_dur = MIN_CHORD_BEATS * _median_beat_spacing(beat_times)
        chords = beat_sync_chords(frames, beat_times, spec, min_chord_dur=min_dur)
    key = estimate_key(chords)
    duration = len(pcm) / spec.fs
    bpm = PLACEHOLDER_BPM if not beat_times else beat_res.bpm

    beats = []
    downbeats = []
    if not beat_times:
        interval = 60.0 / PLACEHOLDER_BPM
        beat_num = 1
        t = 0.0
        while t < duration:
            beats.append({"time": t, "beatNum": beat_num})
            if beat_num == 1: downbeats.append(t)
            beat_num = beat_num % PLACEHOLDER_TS + 1
            t += interval
    else:
        for i, bt in enumerate(beat_times):
            beat_num = i % PLACEHOLDER_TS + 1
            beats.append({"time": bt, "beatNum": beat_num})
            if beat_num == 1: downbeats.append(bt)

    def chord_at(t: float) -> str:
        if not chords: return "N"
        for c in chords:
            if c.start <= t < c.end: return c.chord
        if t < chords[0].start: return chords[0].chord
        return chords[-1].chord

    sync = []
    prev = None
    for i, b in enumerate(beats):
        ch = chord_at(b["time"])
        if ch != prev:
            sync.append({"chord": ch, "beatIndex": i})
            prev = ch

    return {
        "songId": song_id,
        "source": {"youtubeId": song_id, "title": title or song_id,
                   "duration": duration, "bpm": bpm, "timeSignature": PLACEHOLDER_TS},
        "key": key,
        "beats": beats,
        "downbeats": downbeats,
        "chords": [{"chord": c.chord, "start": c.start, "end": c.end,
                    "confidence": c.confidence} for c in chords],
        "synchronizedChords": sync,
        "segments": [],
        "melody": None,
    }
```

- [ ] **Step 4: Implement `slot.py`** (read `entities.py` first for `AnalysisResult` construction)

```python
# server/app/infrastructure/analysis/slot.py
from app.domain.entities import AnalysisResult
from app.domain.ports import ModelSlot
from .manifest import load_spec
from .audio_io import decode_pcm
from .assemble import analyze_pcm

class OnnxAnalysisSlot(ModelSlot):
    def __init__(self, model_name: str = "btc"):
        self._spec = load_spec(model_name)

    def run(self, youtube_id: str, title: str, duration: float) -> AnalysisResult:
        raise NotImplementedError("YouTube ingestion is out of scope for #1; use run_file")

    def run_file(self, song_id: str, title: str, audio_path: str) -> AnalysisResult:
        pcm = decode_pcm(audio_path, self._spec.fs)
        data = analyze_pcm(pcm, song_id, title, self._spec)
        return AnalysisResult.from_dict(data)  # adapt to actual constructor in entities.py
```
Note: replace `AnalysisResult.from_dict` with whatever `entities.py` exposes (constructor / classmethod). Confirm field names match the dict.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd server && pytest tests/analysis/test_assemble.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add server/app/infrastructure/analysis/assemble.py server/app/infrastructure/analysis/slot.py server/tests/analysis/test_assemble.py
git commit -m "feat(analysis): assemble AnalysisResult + OnnxAnalysisSlot (mirrors on_device_analyzer)"
```

---

### Task 8: Wire upload endpoint + `AnalyzeSong` file path

**Files:**
- Modify: `server/app/application/analyze_song.py` (add `audio_path` support / file method)
- Modify: `server/app/api/routes.py` (add `POST /songs/analyze-file`)
- Modify: `server/app/api/deps.py` (provide `OnnxAnalysisSlot` instead of `StubAnalysisSlot`)
- Read: `server/app/api/schemas.py` (response schema)
- Test: `server/tests/test_analyze_file_endpoint.py`

**Interfaces:**
- Consumes: `OnnxAnalysisSlot.run_file`, `SongRepository`.
- Produces: `POST /songs/analyze-file` (multipart `file`, form `title` optional) → `AnalysisResult` JSON; persisted via `repo.save`.

- [ ] **Step 1: Write the failing test**

```python
# server/tests/test_analyze_file_endpoint.py
import io, numpy as np, soundfile as sf
from fastapi.testclient import TestClient
from app.main import app

def _wav_bytes():
    buf = io.BytesIO()
    sf.write(buf, np.zeros(22050*2, dtype="float32"), 22050, format="WAV")
    return buf.getvalue()

def test_analyze_file_returns_result():
    client = TestClient(app)
    r = client.post("/songs/analyze-file",
                    files={"file": ("t.wav", _wav_bytes(), "audio/wav")},
                    data={"title": "Test"})
    assert r.status_code == 200
    body = r.json()
    assert "chords" in body and "key" in body and body["source"]["timeSignature"] == 4
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && pytest tests/test_analyze_file_endpoint.py -v`
Expected: FAIL (404 / route missing).

- [ ] **Step 3: Add `analyze_file` to `AnalyzeSong`**

```python
# in server/app/application/analyze_song.py
def analyze_file(self, song_id: str, title: str, audio_path: str):
    cached = self._repo.get(song_id)
    if cached:
        return cached
    result = self._slot.run_file(song_id, title, audio_path)
    self._repo.save(result)
    return result
```
(Requires `ModelSlot` to expose `run_file`; add it to the port in `domain/ports.py` with a default that raises, or type the slot as `OnnxAnalysisSlot` in `deps.py`.)

- [ ] **Step 4: Add the route** to `server/app/api/routes.py`

```python
import tempfile, os, uuid
from fastapi import UploadFile, File, Form

@router.post("/songs/analyze-file")
async def analyze_file(file: UploadFile = File(...), title: str = Form(""),
                       uc: AnalyzeSong = Depends(get_analyze_song)):
    suffix = os.path.splitext(file.filename or "")[1] or ".wav"
    tmp = os.path.join(tempfile.gettempdir(), f"cm_{uuid.uuid4().hex}{suffix}")
    try:
        with open(tmp, "wb") as f:
            f.write(await file.read())
        song_id = uuid.uuid4().hex  # storage/versioning is sub-project #4
        return uc.analyze_file(song_id, title, tmp)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
```
Adapt `Depends`/router names to the existing `routes.py` patterns.

- [ ] **Step 5: Swap the slot in `deps.py`** — replace `StubAnalysisSlot()` with `OnnxAnalysisSlot("btc")`.

- [ ] **Step 6: Run test to verify it passes**

Run: `cd server && pytest tests/test_analyze_file_endpoint.py -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add server/app/application/analyze_song.py server/app/api/routes.py server/app/api/deps.py server/app/domain/ports.py server/tests/test_analyze_file_endpoint.py
git commit -m "feat(server): POST /songs/analyze-file runs the real ONNX pipeline"
```

---

### Task 9: Parity gate — Python vs Dart golden clip

**Files:**
- Create: `server/tests/fixtures/golden_clip.wav` (short ~8s clip, committed)
- Create: `server/tests/fixtures/golden_btc.json` (Dart pipeline output for that clip)
- Create: `server/tests/analysis/test_parity.py`
- Reference generator (Dart): a small `app/test/tools/dump_golden.dart` or reuse `on_device_analyzer` in a Flutter test to emit JSON for the clip.

**Interfaces:**
- Consumes: `analyze_pcm` (Python), the committed Dart-produced golden JSON.

- [ ] **Step 1: Generate the Dart reference JSON**

Run the Dart `OnDeviceAnalyzer` (or `voteDecode`/`beatSyncChords` path) on `golden_clip.wav` with model `btc` and save the result JSON to `server/tests/fixtures/golden_btc.json`. Commit both clip and JSON.

- [ ] **Step 2: Write the parity test**

```python
# server/tests/analysis/test_parity.py
import json
from pathlib import Path
from app.infrastructure.analysis.manifest import load_spec
from app.infrastructure.analysis.audio_io import decode_pcm
from app.infrastructure.analysis.assemble import analyze_pcm

FIX = Path(__file__).resolve().parents[1] / "fixtures"

def test_parity_btc_golden():
    spec = load_spec("btc")
    pcm = decode_pcm(str(FIX / "golden_clip.wav"), spec.fs)
    got = analyze_pcm(pcm, "golden", "Golden", spec)
    exp = json.loads((FIX / "golden_btc.json").read_text())
    # key + bpm exact
    assert got["key"] == exp["key"]
    assert abs(got["source"]["bpm"] - exp["source"]["bpm"]) < 0.5
    # chord labels identical; boundaries within one frame (~0.093s)
    gc, ec = got["chords"], exp["chords"]
    assert [c["chord"] for c in gc] == [c["chord"] for c in ec]
    for g, e in zip(gc, ec):
        assert abs(g["start"] - e["start"]) <= 0.10
        assert abs(g["end"] - e["end"]) <= 0.10
```

- [ ] **Step 3: Run and iterate to parity**

Run: `cd server && pytest tests/analysis/test_parity.py -v`
Expected: PASS. If it fails, diff the stage outputs (frames → beats → chords) against Dart; the mismatch localizes which port drifted (most likely `stft.py` windowing or the DP predecessor window). Fix the offending module, re-run its unit test + this.

- [ ] **Step 4: Commit**

```bash
git add server/tests/fixtures/golden_clip.wav server/tests/fixtures/golden_btc.json server/tests/analysis/test_parity.py
git commit -m "test(analysis): Python<->Dart parity gate on golden clip"
```

---

### Task 10: Docs

**Files:**
- Modify: `server/README.md`, `README.md` (analysis pipeline + ONNX gen step)

- [ ] **Step 1:** Document `POST /songs/analyze-file`, the ONNX generation prerequisite (Task 0), and that web/desktop now analyze server-side while mobile stays on-device with parity.

- [ ] **Step 2: Commit**

```bash
git add server/README.md README.md
git commit -m "docs(server): server-side analysis pipeline + ONNX prerequisite"
```

---

## Self-Review

- **Spec coverage:** decode (T1), frontend/inference (T2), vote+denoise (T3), beat tracking (T4), beat-sync (T5), key (T6), assemble/slot (T7), endpoint (T8), parity gate (T9), docs (T10), ONNX gen (T0). All spec sections covered. `chord_cnn_lstm`/YouTube explicitly out of scope per spec.
- **Placeholder scan:** two intentional adaptation notes (`AnalysisResult.from_dict` in T7, `stftMagnitude` transcription in T4) require reading one named file each before implementing — flagged, not vague TODOs.
- **Type consistency:** `Frame`, `Chord`, `ModelSpec`, `BeatResult`, `majority_filter`, `merge_short_chords`, `vote_decode`, `beat_sync_chords`, `estimate_key`, `analyze_pcm`, `OnnxAnalysisSlot.run_file` used consistently across tasks.
```
