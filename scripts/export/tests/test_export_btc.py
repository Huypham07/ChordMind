import pytest, numpy as np, onnxruntime as ort
from pathlib import Path
from scripts.export.export_chordnet import export_btc
from scripts.export.config import REFERENCE_ROOT, FEATURE

CKPT = REFERENCE_ROOT / "checkpoints" / "btc_model_best.pth"

@pytest.mark.skipif(not CKPT.exists(), reason="checkpoint not present")
def test_onnx_runs_and_shape(tmp_path):
    out = export_btc(CKPT, tmp_path / "btc.onnx")
    sess = ort.InferenceSession(str(out))
    # Same fixed-window requirement as ChordNet: BTC's positional encoding
    # is also fixed to seq_len=108, so the sample count must be exactly
    # (seq_len - 1) * hop_length to yield 108 CQT frames.
    n = (FEATURE.seq_len - 1) * FEATURE.hop_length
    pcm = np.zeros((1, n), dtype=np.float32)
    logits = sess.run(None, {"pcm": pcm})[0]
    assert logits.shape == (1, FEATURE.seq_len, FEATURE.n_classes)
