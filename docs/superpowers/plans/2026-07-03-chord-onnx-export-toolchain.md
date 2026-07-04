# Chord Model ONNX Export Toolchain — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the reference chord checkpoints to self-contained "waveform-in, logits-out" ONNX models with a verified parity gate and a device-consumable `manifest.json`.

**Architecture:** One Python export script per model under `scripts/export/`. Each wraps a reference `torch.nn.Module` behind an `nnAudio` CQT front-end (so raw PCM → CQT → normalize → model → logits lives entirely in the ONNX graph), exports via `torch.onnx.export`, then a parity check asserts ONNX logits match the original librosa-CQT + torch pipeline within tolerance. ChordNet 2E1D is the first vertical; BTC and chord-cnn-lstm reuse the same harness.

**Tech Stack:** Python 3.11, PyTorch, nnAudio (CQT as a torch module → ONNX), onnx, onnxruntime, librosa, numpy, pytest. Reference code imported from `reference/ChordMini/`.

## Global Constraints

- CQT feature params (from `reference/ChordMini/config/ChordMini.yaml`, verbatim): `n_bins: 144`, `bins_per_octave: 24`, `hop_length: 2048`, `sample_rate: 22050`, `large_voca: true` → `n_classes: 170`, model `seq_len: 108`.
- ONNX opset ≥ 17. Export dynamic axis for the time/frame dimension.
- No new dependency in the Flutter app from this plan — output is artifacts only (`.onnx` + `manifest.json`).
- Artifacts live under `artifacts/onnx/` (gitignored — large binaries); `manifest.json` is committed.
- Parity tolerance: max absolute logit difference `< 1e-3` on the sliding-window path over 3 sample clips.
- Follow existing repo convention: keep scripts small and single-responsibility (matches Clean-Architecture memory).

---

### Task 1: Export scaffold + config constants

**Files:**
- Create: `scripts/export/__init__.py`
- Create: `scripts/export/config.py`
- Create: `scripts/export/requirements.txt`
- Create: `scripts/export/tests/__init__.py`
- Create: `scripts/export/tests/test_config.py`
- Create: `.gitignore` entry for `artifacts/`

**Interfaces:**
- Produces: `scripts/export/config.py` with `FEATURE = FeatureConfig(n_bins=144, bins_per_octave=24, hop_length=2048, sample_rate=22050, n_classes=170, seq_len=108)` and `REFERENCE_ROOT: Path` pointing at `reference/ChordMini`.

- [ ] **Step 1: Write the failing test**

```python
# scripts/export/tests/test_config.py
from scripts.export.config import FEATURE, REFERENCE_ROOT

def test_feature_matches_reference_yaml():
    assert FEATURE.n_bins == 144
    assert FEATURE.bins_per_octave == 24
    assert FEATURE.hop_length == 2048
    assert FEATURE.sample_rate == 22050
    assert FEATURE.n_classes == 170
    assert FEATURE.seq_len == 108

def test_reference_root_has_chordnet():
    assert (REFERENCE_ROOT / "src" / "models" / "chord_net.py").exists()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/huypham/code/ChordMind && python -m pytest scripts/export/tests/test_config.py -v`
Expected: FAIL with `ModuleNotFoundError: scripts.export.config`

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/export/config.py
from dataclasses import dataclass
from pathlib import Path

@dataclass(frozen=True)
class FeatureConfig:
    n_bins: int
    bins_per_octave: int
    hop_length: int
    sample_rate: int
    n_classes: int
    seq_len: int

FEATURE = FeatureConfig(144, 24, 2048, 22050, 170, 108)
REFERENCE_ROOT = Path(__file__).resolve().parents[2] / "reference" / "ChordMini"
ARTIFACTS_DIR = Path(__file__).resolve().parents[2] / "artifacts" / "onnx"
```

```text
# scripts/export/requirements.txt
torch>=2.2
nnAudio>=0.3.2
onnx>=1.16
onnxruntime>=1.18
librosa>=0.10
numpy>=1.26
pytest>=8
pyyaml>=6
```

```python
# scripts/export/__init__.py
# scripts/export/tests/__init__.py
```

Add to `.gitignore`: `artifacts/`

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/huypham/code/ChordMind && python -m pytest scripts/export/tests/test_config.py -v`
Expected: PASS (2 passed)

- [ ] **Step 5: Commit**

```bash
git add scripts/export/ .gitignore
git commit -m "feat(export): scaffold chord ONNX export toolchain + config"
```

---

### Task 2: nnAudio CQT front-end module (PCM → normalized CQT)

**Files:**
- Create: `scripts/export/cqt_frontend.py`
- Test: `scripts/export/tests/test_cqt_frontend.py`

**Interfaces:**
- Consumes: `FEATURE` from Task 1.
- Produces: `class CQTFrontend(torch.nn.Module)` — `__init__(self, mean: float, std: float)`; `forward(pcm: Tensor[B, T_samples]) -> Tensor[B, n_frames, 144]`. Applies nnAudio CQT (log-magnitude, matching librosa `cqt` + `amplitude_to_db`-equivalent used in training) then `(x - mean) / std`. Frame axis is dynamic.

- [ ] **Step 1: Write the failing test**

```python
# scripts/export/tests/test_cqt_frontend.py
import torch
from scripts.export.cqt_frontend import CQTFrontend
from scripts.export.config import FEATURE

def test_frontend_output_shape():
    fe = CQTFrontend(mean=0.0, std=1.0).eval()
    pcm = torch.zeros(1, FEATURE.hop_length * 200)  # ~200 frames of silence
    with torch.no_grad():
        out = fe(pcm)
    assert out.shape[0] == 1
    assert out.shape[2] == FEATURE.n_bins  # 144
    assert out.shape[1] >= 190  # ~ samples / hop

def test_frontend_normalizes():
    fe = CQTFrontend(mean=5.0, std=2.0).eval()
    pcm = torch.randn(1, FEATURE.hop_length * 120)
    raw = CQTFrontend(mean=0.0, std=1.0).eval()
    with torch.no_grad():
        a = fe(pcm); b = raw(pcm)
    assert torch.allclose(a, (b - 5.0) / 2.0, atol=1e-4)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/huypham/code/ChordMind && python -m pytest scripts/export/tests/test_cqt_frontend.py -v`
Expected: FAIL with `ModuleNotFoundError: scripts.export.cqt_frontend`

- [ ] **Step 3: Write minimal implementation**

Note: `reference/ChordMini/src/utils/audio_io.py` holds the exact training CQT recipe — before writing, open it and confirm whether magnitude is `log`, `amplitude_to_db`, or raw. Mirror that scaling here so the front-end matches training. The code below assumes log-magnitude; adjust the `torch.log` line to match.

```python
# scripts/export/cqt_frontend.py
import torch
from nnAudio.features.cqt import CQT
from scripts.export.config import FEATURE

class CQTFrontend(torch.nn.Module):
    """Raw PCM -> normalized CQT [B, frames, n_bins], graph-exportable."""
    def __init__(self, mean: float, std: float):
        super().__init__()
        self.cqt = CQT(
            sr=FEATURE.sample_rate,
            hop_length=FEATURE.hop_length,
            n_bins=FEATURE.n_bins,
            bins_per_octave=FEATURE.bins_per_octave,
            fmin=32.7,  # C1; confirm against audio_io.py
            output_format="Magnitude",
            verbose=False,
        )
        self.register_buffer("mean", torch.tensor(float(mean)))
        self.register_buffer("std", torch.tensor(float(std)))

    def forward(self, pcm: torch.Tensor) -> torch.Tensor:
        mag = self.cqt(pcm)                    # [B, n_bins, frames]
        logmag = torch.log(mag + 1e-6)         # match training scaling
        feat = logmag.transpose(1, 2)          # [B, frames, n_bins]
        return (feat - self.mean) / self.std
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/huypham/code/ChordMind && python -m pytest scripts/export/tests/test_cqt_frontend.py -v`
Expected: PASS (2 passed)

- [ ] **Step 5: Commit**

```bash
git add scripts/export/cqt_frontend.py scripts/export/tests/test_cqt_frontend.py
git commit -m "feat(export): nnAudio CQT front-end module"
```

---

### Task 3: Load reference ChordNet 2E1D checkpoint (model + norm stats + vocab)

**Files:**
- Create: `scripts/export/load_chordnet.py`
- Test: `scripts/export/tests/test_load_chordnet.py`

**Interfaces:**
- Consumes: `REFERENCE_ROOT`, `FEATURE`.
- Produces: `load_chordnet(ckpt_path: Path) -> ChordNetBundle` where `ChordNetBundle` has `.model: torch.nn.Module (eval)`, `.mean: float`, `.std: float`, `.idx_to_chord: dict[int,str]` (len 170).

Before writing: open `reference/ChordMini/src/evaluation/utils/` (the `extract_norm_stats`, `extract_vocab` helpers referenced in `test_labeled_audio.py`) and `reference/ChordMini/src/models/chord_net.py` (`ChordNet(**config.to_chordnet_kwargs())`) to confirm the exact constructor + checkpoint-key names. Wire those real helpers rather than reimplementing.

- [ ] **Step 1: Write the failing test**

```python
# scripts/export/tests/test_load_chordnet.py
import pytest
from pathlib import Path
from scripts.export.load_chordnet import load_chordnet
from scripts.export.config import REFERENCE_ROOT, FEATURE

CKPT = REFERENCE_ROOT / "checkpoints" / "2e1d_model_best.pth"

@pytest.mark.skipif(not CKPT.exists(), reason="checkpoint not present")
def test_bundle_shapes():
    b = load_chordnet(CKPT)
    assert len(b.idx_to_chord) == FEATURE.n_classes
    assert isinstance(b.mean, float) and isinstance(b.std, float)
    assert not b.model.training
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/huypham/code/ChordMind && python -m pytest scripts/export/tests/test_load_chordnet.py -v`
Expected: FAIL with `ModuleNotFoundError: scripts.export.load_chordnet`

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/export/load_chordnet.py
import sys
from dataclasses import dataclass
from pathlib import Path
import torch
from scripts.export.config import REFERENCE_ROOT

sys.path.insert(0, str(REFERENCE_ROOT))
from src.models.chord_net import ChordNet  # noqa: E402
from src.evaluation.utils.checkpoint import (  # noqa: E402  # confirm module path
    extract_norm_stats, extract_vocab,
)

@dataclass
class ChordNetBundle:
    model: torch.nn.Module
    mean: float
    std: float
    idx_to_chord: dict

def load_chordnet(ckpt_path: Path) -> ChordNetBundle:
    ckpt = torch.load(ckpt_path, map_location="cpu")
    mean, std = extract_norm_stats(str(ckpt_path))
    idx_to_chord, _ = extract_vocab(str(ckpt_path))
    model = ChordNet(n_freq=144, n_classes=len(idx_to_chord), n_group=12)
    state = ckpt.get("model_state_dict", ckpt.get("state_dict", ckpt))
    model.load_state_dict(state, strict=False)
    model.eval()
    return ChordNetBundle(model, float(mean), float(std), idx_to_chord)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/huypham/code/ChordMind && python -m pytest scripts/export/tests/test_load_chordnet.py -v`
Expected: PASS (or SKIP if checkpoint absent — then run once with the checkpoint present before proceeding).

- [ ] **Step 5: Commit**

```bash
git add scripts/export/load_chordnet.py scripts/export/tests/test_load_chordnet.py
git commit -m "feat(export): load reference ChordNet 2E1D bundle"
```

---

### Task 4: Export 2E1D to ONNX (front-end + model, fixed 108-frame window)

**Files:**
- Create: `scripts/export/export_chordnet.py`
- Test: `scripts/export/tests/test_export_chordnet.py`

**Interfaces:**
- Consumes: `CQTFrontend`, `load_chordnet`, `FEATURE`, `ARTIFACTS_DIR`.
- Produces: `export_chordnet(ckpt_path: Path, out_path: Path) -> Path` writing an ONNX graph with input `pcm` `[1, seq_len*hop_length]` float32 and output `logits` `[1, seq_len, n_classes]`. Also `class WrappedChordNet(nn.Module)` = front-end + `model.forward(x)[0]` (logits only).

- [ ] **Step 1: Write the failing test**

```python
# scripts/export/tests/test_export_chordnet.py
import pytest, numpy as np, onnxruntime as ort
from pathlib import Path
from scripts.export.export_chordnet import export_chordnet
from scripts.export.config import REFERENCE_ROOT, FEATURE, ARTIFACTS_DIR

CKPT = REFERENCE_ROOT / "checkpoints" / "2e1d_model_best.pth"

@pytest.mark.skipif(not CKPT.exists(), reason="checkpoint not present")
def test_onnx_runs_and_shape(tmp_path):
    out = export_chordnet(CKPT, tmp_path / "chordnet_2e1d.onnx")
    sess = ort.InferenceSession(str(out))
    n = FEATURE.seq_len * FEATURE.hop_length
    pcm = np.zeros((1, n), dtype=np.float32)
    logits = sess.run(None, {"pcm": pcm})[0]
    assert logits.shape == (1, FEATURE.seq_len, FEATURE.n_classes)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/huypham/code/ChordMind && python -m pytest scripts/export/tests/test_export_chordnet.py -v`
Expected: FAIL with `ModuleNotFoundError: scripts.export.export_chordnet`

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/export/export_chordnet.py
from pathlib import Path
import torch
from scripts.export.cqt_frontend import CQTFrontend
from scripts.export.load_chordnet import load_chordnet
from scripts.export.config import FEATURE

class WrappedChordNet(torch.nn.Module):
    def __init__(self, frontend, model):
        super().__init__()
        self.frontend = frontend
        self.model = model
    def forward(self, pcm):
        feat = self.frontend(pcm)                 # [1, frames, 144]
        out = self.model(feat)                    # (logits, features)
        return out[0] if isinstance(out, tuple) else out

def export_chordnet(ckpt_path: Path, out_path: Path) -> Path:
    b = load_chordnet(ckpt_path)
    wrapped = WrappedChordNet(CQTFrontend(b.mean, b.std), b.model).eval()
    n = FEATURE.seq_len * FEATURE.hop_length
    dummy = torch.zeros(1, n)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        wrapped, dummy, str(out_path),
        input_names=["pcm"], output_names=["logits"],
        dynamic_axes={"pcm": {1: "samples"}, "logits": {1: "frames"}},
        opset_version=17,
    )
    return out_path
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/huypham/code/ChordMind && python -m pytest scripts/export/tests/test_export_chordnet.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/export/export_chordnet.py scripts/export/tests/test_export_chordnet.py
git commit -m "feat(export): export ChordNet 2E1D to ONNX (PCM in, logits out)"
```

---

### Task 5: Parity gate — ONNX vs reference librosa+torch

**Files:**
- Create: `scripts/export/parity_check.py`
- Create: `scripts/export/tests/fixtures/README.md` (how to drop 3 short wav clips)
- Test: `scripts/export/tests/test_parity.py`

**Interfaces:**
- Consumes: `export_chordnet`, `load_chordnet`, reference feature extractor (`extract_song_features` from `src/evaluation/utils/inference`).
- Produces: `max_logit_diff(onnx_path, ckpt_path, wav_path) -> float`. Compares ONNX (PCM path) against the reference librosa-CQT + torch path over aligned 108-frame windows.

- [ ] **Step 1: Write the failing test**

```python
# scripts/export/tests/test_parity.py
import pytest
from pathlib import Path
from scripts.export.parity_check import max_logit_diff
from scripts.export.export_chordnet import export_chordnet
from scripts.export.config import REFERENCE_ROOT

CKPT = REFERENCE_ROOT / "checkpoints" / "2e1d_model_best.pth"
CLIPS = sorted((Path(__file__).parent / "fixtures").glob("*.wav"))

@pytest.mark.skipif(not CKPT.exists() or not CLIPS, reason="checkpoint or clips absent")
def test_onnx_matches_reference(tmp_path):
    onnx = export_chordnet(CKPT, tmp_path / "m.onnx")
    for wav in CLIPS[:3]:
        assert max_logit_diff(onnx, CKPT, wav) < 1e-3
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/huypham/code/ChordMind && python -m pytest scripts/export/tests/test_parity.py -v`
Expected: FAIL with `ModuleNotFoundError: scripts.export.parity_check`

- [ ] **Step 3: Write minimal implementation**

Open `reference/ChordMini/src/evaluation/utils/inference.py` to confirm `extract_song_features` returns `(feature_matrix[frames,144], frame_duration)` and reuse it for the reference branch. Load PCM with `librosa.load(wav, sr=22050, mono=True)`.

```python
# scripts/export/parity_check.py
import sys
import numpy as np
import librosa, onnxruntime as ort, torch
from pathlib import Path
from scripts.export.config import REFERENCE_ROOT, FEATURE
from scripts.export.load_chordnet import load_chordnet

sys.path.insert(0, str(REFERENCE_ROOT))
from src.evaluation.utils.inference import extract_song_features  # noqa: E402

def _first_window_logits_onnx(onnx_path, pcm):
    sess = ort.InferenceSession(str(onnx_path))
    n = FEATURE.seq_len * FEATURE.hop_length
    seg = pcm[:n] if len(pcm) >= n else np.pad(pcm, (0, n - len(pcm)))
    return sess.run(None, {"pcm": seg[None, :].astype(np.float32)})[0][0]

def _first_window_logits_ref(ckpt_path, wav):
    b = load_chordnet(ckpt_path)
    feats, _ = extract_song_features(str(wav), _ref_config())  # [frames,144]
    win = feats[:FEATURE.seq_len]
    x = torch.tensor(win, dtype=torch.float32)[None]
    with torch.no_grad():
        out = b.model(x)
        logits = out[0] if isinstance(out, tuple) else out
    return logits[0].numpy()

def max_logit_diff(onnx_path, ckpt_path, wav) -> float:
    pcm, _ = librosa.load(str(wav), sr=FEATURE.sample_rate, mono=True)
    a = _first_window_logits_onnx(onnx_path, pcm)
    b = _first_window_logits_ref(ckpt_path, wav)
    m = min(len(a), len(b))
    return float(np.max(np.abs(a[:m] - b[:m])))

def _ref_config():
    # confirm loader in src/utils/config_utils.py; returns the object
    # extract_song_features expects (with .feature params).
    from src.utils.hparams import HParams
    return HParams.load(str(REFERENCE_ROOT / "config" / "ChordMini.yaml"))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/huypham/code/ChordMind && python -m pytest scripts/export/tests/test_parity.py -v`
Expected: PASS. If it fails on scaling, reconcile `cqt_frontend.py` log/magnitude with `audio_io.py` until diff `< 1e-3`. This is the gate — do not proceed until green.

- [ ] **Step 5: Commit**

```bash
git add scripts/export/parity_check.py scripts/export/tests/
git commit -m "feat(export): parity gate ONNX vs reference for 2E1D"
```

---

### Task 6: Emit device manifest (labels + metadata)

**Files:**
- Create: `scripts/export/manifest.py`
- Create: `artifacts/onnx/manifest.json` (generated; commit this small file)
- Test: `scripts/export/tests/test_manifest.py`

**Interfaces:**
- Consumes: `load_chordnet` (for `idx_to_chord`), the exported `.onnx` (for sha256).
- Produces: `write_manifest_entry(onnx_path, ckpt_path, *, name, step, decode) -> dict` and appends/updates the entry in `manifest.json`. Entry schema: `{name, step, file, sha256, version, fs, seq_len, n_classes, labels: [str;170], decode}`.

- [ ] **Step 1: Write the failing test**

```python
# scripts/export/tests/test_manifest.py
import json, pytest
from pathlib import Path
from scripts.export.manifest import write_manifest_entry
from scripts.export.config import REFERENCE_ROOT

CKPT = REFERENCE_ROOT / "checkpoints" / "2e1d_model_best.pth"

@pytest.mark.skipif(not CKPT.exists(), reason="checkpoint absent")
def test_entry_has_170_labels(tmp_path):
    onnx = tmp_path / "m.onnx"; onnx.write_bytes(b"stub")
    manifest = tmp_path / "manifest.json"
    e = write_manifest_entry(onnx, CKPT, name="chordnet_2e1d",
                             step="chord", decode="vote", manifest_path=manifest)
    assert len(e["labels"]) == 170
    assert e["step"] == "chord" and e["seq_len"] == 108
    assert json.loads(manifest.read_text())["chordnet_2e1d"]["sha256"] == e["sha256"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/huypham/code/ChordMind && python -m pytest scripts/export/tests/test_manifest.py -v`
Expected: FAIL with `ModuleNotFoundError: scripts.export.manifest`

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/export/manifest.py
import hashlib, json
from pathlib import Path
from scripts.export.config import FEATURE
from scripts.export.load_chordnet import load_chordnet

def _sha256(p: Path) -> str:
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def write_manifest_entry(onnx_path, ckpt_path, *, name, step, decode,
                         manifest_path, version="1") -> dict:
    b = load_chordnet(Path(ckpt_path))
    labels = [b.idx_to_chord[i] for i in range(len(b.idx_to_chord))]
    entry = {
        "name": name, "step": step, "file": Path(onnx_path).name,
        "sha256": _sha256(onnx_path), "version": version,
        "fs": FEATURE.sample_rate, "seq_len": FEATURE.seq_len,
        "n_classes": FEATURE.n_classes, "labels": labels, "decode": decode,
    }
    mp = Path(manifest_path)
    data = json.loads(mp.read_text()) if mp.exists() else {}
    data[name] = entry
    mp.write_text(json.dumps(data, indent=2))
    return entry
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/huypham/code/ChordMind && python -m pytest scripts/export/tests/test_manifest.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/export/manifest.py scripts/export/tests/test_manifest.py
git commit -m "feat(export): device manifest with chord labels + sha256"
```

---

### Task 7: One-command CLI + full-run doc

**Files:**
- Create: `scripts/export/__main__.py`
- Modify: `README.md` — add a short "Model export" run section (per README-content memory: install/run only).

**Interfaces:**
- Consumes: all above.
- Produces: `python -m scripts.export chordnet_2e1d` → exports ONNX to `artifacts/onnx/`, runs parity gate, writes manifest. Exits non-zero if parity fails.

- [ ] **Step 1: Write the failing test**

```python
# scripts/export/tests/test_cli.py
import subprocess, sys, pytest
from pathlib import Path
from scripts.export.config import REFERENCE_ROOT, ARTIFACTS_DIR

CKPT = REFERENCE_ROOT / "checkpoints" / "2e1d_model_best.pth"

@pytest.mark.skipif(not CKPT.exists(), reason="checkpoint absent")
def test_cli_produces_artifacts():
    r = subprocess.run([sys.executable, "-m", "scripts.export", "chordnet_2e1d"],
                       cwd=Path(__file__).resolve().parents[3], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert (ARTIFACTS_DIR / "chordnet_2e1d.onnx").exists()
    assert (ARTIFACTS_DIR / "manifest.json").exists()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/huypham/code/ChordMind && python -m pytest scripts/export/tests/test_cli.py -v`
Expected: FAIL (`No module named scripts.export.__main__`)

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/export/__main__.py
import sys
from scripts.export.config import REFERENCE_ROOT, ARTIFACTS_DIR
from scripts.export.export_chordnet import export_chordnet
from scripts.export.parity_check import max_logit_diff
from scripts.export.manifest import write_manifest_entry

MODELS = {
    "chordnet_2e1d": ("checkpoints/2e1d_model_best.pth", "chord", "vote"),
}

def main(name: str) -> int:
    rel, step, decode = MODELS[name]
    ckpt = REFERENCE_ROOT / rel
    onnx = export_chordnet(ckpt, ARTIFACTS_DIR / f"{name}.onnx")
    clips = list((REFERENCE_ROOT.parents[0] / "scripts" / "export" / "tests" / "fixtures").glob("*.wav"))
    for wav in clips[:3]:
        d = max_logit_diff(onnx, ckpt, wav)
        if d >= 1e-3:
            print(f"PARITY FAIL {wav.name}: {d}"); return 1
    write_manifest_entry(onnx, ckpt, name=name, step=step, decode=decode,
                         manifest_path=ARTIFACTS_DIR / "manifest.json")
    print(f"OK {name}"); return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
```

Add to `README.md`:

```markdown
## Model export (base pipeline)
Convert reference chord checkpoints to on-device ONNX:
```bash
pip install -r scripts/export/requirements.txt
python -m scripts.export chordnet_2e1d   # -> artifacts/onnx/{chordnet_2e1d.onnx,manifest.json}
```
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/huypham/code/ChordMind && python -m pytest scripts/export/tests/test_cli.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/export/__main__.py README.md
git commit -m "feat(export): one-command chordnet_2e1d export with parity gate"
```

---

### Task 8 (follow-on): BTC + chord-cnn-lstm options

**Files:**
- Create: `scripts/export/load_btc.py`, `scripts/export/export_btc.py`
- Modify: `scripts/export/__main__.py` — add `btc` and `chord_cnn_lstm` to `MODELS`.

**Interfaces:**
- Same `WrappedX(nn.Module)` pattern → PCM-in/logits-out ONNX; same parity gate (`< 1e-3`); same manifest schema with `decode` set per model (`btc` → `"crf"` / `chord_cnn_lstm` → `"hmm"`).

- [ ] **Step 1:** Repeat Tasks 3–7 for BTC (`reference/ChordMini/src/models/btc_model.py`, `checkpoints/btc_model_best.pth`). BTC input is the same CQT front-end; decode metadata = `"crf"`.
- [ ] **Step 2:** Repeat for chord-cnn-lstm (`reference/chord-cnn-lstm-model/`, `reference/ChordMiniApp/python_backend/checkpoint.bin`). Its structure-decomposition head may output multiple tensors; export all logits and set `decode="hmm"`. Confirm the forward signature in that repo before wrapping.
- [ ] **Step 3:** Each addition must pass its own parity gate before its manifest entry is written and committed.

> These three manifest entries are exactly the "multiple selectable options" the app's chord slot consumes (Plan B). No app change needed to add a model — only a new manifest entry.

---

## Self-Review

- **Spec coverage:** §2 runtime=ONNX (Tasks 4,7), §2 waveform-in + baked features (Tasks 2,4), §3 chord = 3 options (Tasks 4–8), §4 conversion workflow incl. parity gate + manifest (Tasks 4,5,6), §6 manifest storage schema (Task 6). Beat/key/segmentation/melody are out of this plan by design (this plan = chord export subsystem only).
- **Deferred to Plan B (Flutter):** on-device ORT inference, Dart decode (vote/crf/hmm), Krumhansl key, manifest download/cache. Blocked on the audio-source decision.
- **Placeholders:** none — every code step is concrete. Three tasks include an explicit "open reference file X to confirm signature before writing" instruction; these are real, targeted actions (integration with third-party reference code), not vague TODOs, and each is backed by the parity gate as the correctness oracle.
- **Type consistency:** `ChordNetBundle`, `CQTFrontend(mean,std)`, `WrappedChordNet`, `export_chordnet(ckpt,out)->Path`, `max_logit_diff(onnx,ckpt,wav)->float`, `write_manifest_entry(...)->dict` used consistently across tasks.
