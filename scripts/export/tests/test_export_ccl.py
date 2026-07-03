import numpy as np
import onnxruntime as ort
import pytest
import torch

from scripts.export.config import CCL_REFERENCE_ROOT
from scripts.export.export_ccl import HEAD_NAMES, export_ccl
from scripts.export.load_ccl import CHECKPOINT_STEM, _cqt_v2, load_ccl, reference_probs

CKPT = CCL_REFERENCE_ROOT / "cache_data" / f"{CHECKPOINT_STEM}.sdict"
FIXTURES_DIR = CCL_REFERENCE_ROOT.parents[1] / "scripts" / "export" / "tests" / "fixtures"
TRIAD = FIXTURES_DIR / "triad_cmaj.wav"
EXTENDED = FIXTURES_DIR / "extended_c9.wav"


@pytest.mark.skipif(not CKPT.exists(), reason="s0 checkpoint not present")
def test_dynamic_frame_count_runs_for_two_lengths(tmp_path):
    """The net/LSTM processes a whole song of variable length in one pass,
    so the frames axis must be a real dynamic axis, not a baked-in fixed
    window (unlike the ChordNet/BTC 108-frame export). Prove it by running
    the exported graph at two different frame counts.
    """
    out = export_ccl(tmp_path / "chord_cnn_lstm.onnx")
    sess = ort.InferenceSession(str(out))

    for n_frames in (40, 97):
        feature = np.zeros((n_frames, 288), dtype=np.float32)
        outputs = sess.run(None, {"feature": feature})
        assert len(outputs) == 6
        for out_arr in outputs:
            assert out_arr.shape[0] == n_frames


@pytest.mark.skipif(not CKPT.exists(), reason="s0 checkpoint not present")
@pytest.mark.parametrize("fixture", [TRIAD, EXTENDED], ids=["triad_cmaj", "extended_c9"])
def test_onnx_matches_reference_per_head_argmax(fixture, tmp_path):
    if not fixture.exists():
        pytest.skip(f"fixture not present: {fixture}")

    bundle = load_ccl()
    ref_probs = reference_probs(bundle.net, fixture, sample_rate=bundle.sample_rate)
    expected_dims = tuple(p.shape[1] for p in ref_probs)

    out = export_ccl(tmp_path / "chord_cnn_lstm.onnx")
    sess = ort.InferenceSession(str(out))

    feature = _cqt_v2(fixture, bundle.sample_rate)
    onnx_probs = sess.run(None, {"feature": feature})

    assert len(onnx_probs) == 6
    for name, p_ref, p_onnx, dim in zip(HEAD_NAMES, ref_probs, onnx_probs, expected_dims):
        assert p_onnx.shape[1] == dim, f"{name} head class-dim mismatch: {p_onnx.shape[1]} != {dim}"
        n = min(p_ref.shape[0], p_onnx.shape[0])
        assert n > 50
        a_ref = np.argmax(p_ref[:n], axis=1)
        a_onnx = np.argmax(p_onnx[:n], axis=1)
        agreement = float(np.mean(a_ref == a_onnx))
        assert agreement >= 0.99, f"{name} head argmax agreement {agreement} < 0.99"
