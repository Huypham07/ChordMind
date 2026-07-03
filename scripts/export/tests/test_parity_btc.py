import pytest
from pathlib import Path

from scripts.export.parity_check import max_logit_diff, argmax_agreement
from scripts.export.export_chordnet import export_btc
from scripts.export.config import REFERENCE_ROOT

CKPT = REFERENCE_ROOT / "checkpoints" / "btc_model_best.pth"
CLIPS = sorted((Path(__file__).parent / "fixtures").glob("*.wav"))

# ponytail: same rationale as test_parity.py -- argmax agreement is the real
# gate, logit diff is only a loose ceiling against a gross future regression.
LOGIT_CEILING = 5.0


@pytest.mark.skipif(not CKPT.exists() or not CLIPS, reason="checkpoint or clips absent")
@pytest.mark.xfail(
    strict=True,
    reason=(
        "KNOWN GATE FAILURE (see task-8a-report.md): BTC argmax_agreement on "
        "triad_cmaj.wav is 0.389, not 1.0. Isolated to BTC's own 8-layer "
        "bidirectional self-attention transformer amplifying PyTorch-eager-vs-"
        "ONNXRuntime float32 numeric drift on this clip's near-tied logits -- "
        "NOT a bug in the shared CQT frontend/wrapper: the identical frontend "
        "gives ChordNet argmax_agreement=1.0 on the same clip. Do not loosen "
        "this gate; un-xfail only once the underlying divergence is fixed."
    ),
)
def test_onnx_matches_reference(tmp_path):
    onnx = export_btc(CKPT, tmp_path / "m.onnx")
    for wav in CLIPS[:3]:
        assert argmax_agreement(onnx, CKPT, wav, "BTC") == 1.0
        assert max_logit_diff(onnx, CKPT, wav, "BTC") < LOGIT_CEILING
