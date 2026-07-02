import pytest, numpy as np, onnxruntime as ort
from pathlib import Path
from scripts.export.export_chordnet import export_chordnet
from scripts.export.config import REFERENCE_ROOT, FEATURE, ARTIFACTS_DIR

CKPT = REFERENCE_ROOT / "checkpoints" / "2e1d_model_best.pth"

@pytest.mark.skipif(not CKPT.exists(), reason="checkpoint not present")
def test_onnx_runs_and_shape(tmp_path):
    out = export_chordnet(CKPT, tmp_path / "chordnet_2e1d.onnx")
    sess = ort.InferenceSession(str(out))
    # Note: with center=True CQT framing (librosa/nnAudio default), N samples
    # yields 1 + N // hop_length frames. seq_len * hop_length would yield
    # seq_len + 1 = 109 frames (off-by-one), not the fixed seq_len=108 the
    # model's transformer positional encoding requires. The correct sample
    # count for exactly seq_len frames is (seq_len - 1) * hop_length.
    n = (FEATURE.seq_len - 1) * FEATURE.hop_length
    pcm = np.zeros((1, n), dtype=np.float32)
    logits = sess.run(None, {"pcm": pcm})[0]
    assert logits.shape == (1, FEATURE.seq_len, FEATURE.n_classes)
