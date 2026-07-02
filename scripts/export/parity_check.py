"""Parity gate: ONNX (PCM-in) path vs. reference librosa-CQT + torch path.

Both sides must see the SAME 108-frame window of the SAME audio:
- The ONNX path takes the first `(seq_len - 1) * hop_length` = 219136 PCM
  samples of the clip (padding with zeros if the clip is shorter) and runs
  them through the exported graph, which includes the CQT frontend and its
  (x - mean) / std normalization (see `scripts/export/cqt_frontend.py`).
- The reference path runs the reference `extract_song_features` (raw
  librosa CQT, log-magnitude, NOT normalized -- see
  reference/ChordMini/src/evaluation/utils/common.py:180-199) over the
  full clip, takes the first `seq_len` frames, and applies the SAME
  (x - mean) / std normalization using the checkpoint's own norm stats
  (`ChordNetBundle.mean/.std`, extracted by `load_chordnet`) before
  feeding the reference torch model. Without this explicit normalization
  on the reference side, the comparison would be spurious: the ONNX graph
  normalizes internally but `extract_song_features` does not.
"""
import sys

import librosa
import numpy as np
import onnxruntime as ort
import torch

from scripts.export.config import FEATURE, REFERENCE_ROOT
from scripts.export.load_chordnet import load_chordnet

sys.path.insert(0, str(REFERENCE_ROOT))

from src.evaluation.utils.common import extract_song_features  # noqa: E402
from src.utils import HParams  # noqa: E402

CONFIG_PATH = REFERENCE_ROOT / "config" / "ChordMini.yaml"
WINDOW_SAMPLES = (FEATURE.seq_len - 1) * FEATURE.hop_length


def _ref_config():
    return HParams.load(str(CONFIG_PATH))


def _first_window_logits_onnx(onnx_path, pcm: np.ndarray) -> np.ndarray:
    sess = ort.InferenceSession(str(onnx_path))
    n = WINDOW_SAMPLES
    seg = pcm[:n] if len(pcm) >= n else np.pad(pcm, (0, n - len(pcm)))
    logits = sess.run(None, {"pcm": seg[None, :].astype(np.float32)})[0][0]
    return logits


def _first_window_logits_ref(ckpt_path, wav) -> np.ndarray:
    bundle = load_chordnet(ckpt_path)
    feats, _ = extract_song_features(str(wav), _ref_config())  # [frames, 144], NOT normalized
    win = feats[: FEATURE.seq_len]
    win = (win - bundle.mean) / bundle.std  # match ONNX frontend's normalization
    x = torch.tensor(win, dtype=torch.float32)[None]
    with torch.no_grad():
        out = bundle.model(x)
        logits = out[0] if isinstance(out, tuple) else out
    return logits[0].numpy()


def _paired_logits(onnx_path, ckpt_path, wav):
    pcm, _ = librosa.load(str(wav), sr=FEATURE.sample_rate, mono=True)
    a = _first_window_logits_onnx(onnx_path, pcm)
    b = _first_window_logits_ref(ckpt_path, wav)
    m = min(len(a), len(b))
    return a[:m], b[:m]


def max_logit_diff(onnx_path, ckpt_path, wav) -> float:
    a, b = _paired_logits(onnx_path, ckpt_path, wav)
    return float(np.max(np.abs(a - b)))


def argmax_agreement(onnx_path, ckpt_path, wav) -> float:
    """Fraction of frames where ONNX and reference predict the same chord
    index -- the metric that actually matters for a classifier."""
    a, b = _paired_logits(onnx_path, ckpt_path, wav)
    agree = np.argmax(a, axis=-1) == np.argmax(b, axis=-1)
    return float(np.mean(agree))
