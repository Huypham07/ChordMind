import pytest
from pathlib import Path

from scripts.export.parity_check import max_logit_diff, argmax_agreement
from scripts.export.export_chordnet import export_chordnet
from scripts.export.config import REFERENCE_ROOT

CKPT = REFERENCE_ROOT / "checkpoints" / "2e1d_model_best.pth"
CLIPS = sorted((Path(__file__).parent / "fixtures").glob("*.wav"))

# ponytail: real gate is argmax agreement; this logit ceiling only catches
# gross bugs, nnAudio<->librosa CQT drift makes tight logit parity
# unattainable without baking the librosa CQT basis.
LOGIT_CEILING = 5.0


@pytest.mark.skipif(not CKPT.exists() or not CLIPS, reason="checkpoint or clips absent")
def test_onnx_matches_reference(tmp_path):
    """The metric that actually matters for a classifier: do ONNX and the
    reference agree on the predicted chord per frame? Raw logit diff is
    checked only as a loose ceiling to catch a gross future regression --
    nnAudio's CQT differs numerically from librosa's, so exact logit
    parity is not the gate."""
    onnx = export_chordnet(CKPT, tmp_path / "m.onnx")
    for wav in CLIPS[:3]:
        assert argmax_agreement(onnx, CKPT, wav) == 1.0
        assert max_logit_diff(onnx, CKPT, wav) < LOGIT_CEILING
