import pytest
from pathlib import Path

from scripts.export.parity_check import max_logit_diff, argmax_agreement
from scripts.export.export_chordnet import export_btc
from scripts.export.config import REFERENCE_ROOT

CKPT = REFERENCE_ROOT / "checkpoints" / "btc_model_best.pth"
CLIPS = sorted((Path(__file__).parent / "fixtures").glob("*.wav"))

# ponytail: same rationale as test_parity.py -- argmax agreement is the real
# gate, logit diff is only a loose ceiling against a gross future regression.
# BTC's 8-layer bidirectional transformer amplifies PyTorch-eager-vs-
# ONNXRuntime float32 numeric drift more than ChordNet's shallower stack
# (observed up to ~5.4 on the sweep fixture vs ChordNet's <2.7), so its
# ceiling is looser than test_parity.py's -- still tight enough to catch a
# gross regression (e.g. an off-by-orders-of-magnitude bug).
LOGIT_CEILING = 8.0


@pytest.mark.skipif(not CKPT.exists() or not CLIPS, reason="checkpoint or clips absent")
def test_onnx_matches_reference(tmp_path):
    onnx = export_btc(CKPT, tmp_path / "m.onnx")
    for wav in CLIPS[:3]:
        assert argmax_agreement(onnx, CKPT, wav, "BTC") == 1.0
        assert max_logit_diff(onnx, CKPT, wav, "BTC") < LOGIT_CEILING
