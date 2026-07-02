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
