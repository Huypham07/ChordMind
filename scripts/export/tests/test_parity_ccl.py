import pytest

from scripts.export.config import CCL_REFERENCE_ROOT
from scripts.export.export_ccl import export_ccl
from scripts.export.load_ccl import CHECKPOINT_STEM
from scripts.export.parity_check import ccl_head_agreement

CKPT = CCL_REFERENCE_ROOT / "cache_data" / f"{CHECKPOINT_STEM}.sdict"
FIXTURES_DIR = CCL_REFERENCE_ROOT.parents[1] / "scripts" / "export" / "tests" / "fixtures"
TRIAD = FIXTURES_DIR / "triad_cmaj.wav"
EXTENDED = FIXTURES_DIR / "extended_c9.wav"


@pytest.mark.skipif(not CKPT.exists(), reason="s0 checkpoint not present")
@pytest.mark.parametrize("fixture", [TRIAD, EXTENDED], ids=["triad_cmaj", "extended_c9"])
def test_ccl_head_agreement_all_heads_pass(fixture, tmp_path):
    if not fixture.exists():
        pytest.skip(f"fixture not present: {fixture}")

    onnx = export_ccl(tmp_path / "chord_cnn_lstm.onnx")
    agreements = ccl_head_agreement(onnx, fixture)

    assert len(agreements) == 6
    for agreement in agreements:
        assert agreement >= 0.99
