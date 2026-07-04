import pytest
from scripts.export.load_chordnet import load_btc
from scripts.export.config import REFERENCE_ROOT, FEATURE

CKPT = REFERENCE_ROOT / "checkpoints" / "btc_model_best.pth"


@pytest.mark.skipif(not CKPT.exists(), reason="checkpoint not present")
def test_bundle_shapes():
    b = load_btc(CKPT)
    assert len(b.idx_to_chord) == FEATURE.n_classes
    assert isinstance(b.mean, float) and isinstance(b.std, float)
    assert not b.model.training
