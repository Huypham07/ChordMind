import numpy as np
import pytest
import torch

from scripts.export.ccl_frontend import CCLFrontend
from scripts.export.config import CCL_REFERENCE_ROOT
from scripts.export.load_ccl import CHECKPOINT_STEM, load_ccl, reference_probs
from scripts.export.load_ccl import _cqt_v2

CKPT = CCL_REFERENCE_ROOT / "cache_data" / f"{CHECKPOINT_STEM}.sdict"
FIXTURES_DIR = CCL_REFERENCE_ROOT.parents[1] / "scripts" / "export" / "tests" / "fixtures"
TRIAD = FIXTURES_DIR / "triad_cmaj.wav"
EXTENDED = FIXTURES_DIR / "extended_c9.wav"

HEAD_NAMES = ("triad", "bass", "seventh", "ninth", "eleventh", "thirteenth")


def test_frontend_output_shape():
    fe = CCLFrontend().eval()
    feature = torch.zeros(50, 288)
    with torch.no_grad():
        out = fe(feature)
    assert out.shape == (50, 288)


def test_frontend_rejects_wrong_bin_count():
    fe = CCLFrontend().eval()
    with pytest.raises(ValueError):
        fe(torch.zeros(50, 144))


@pytest.mark.skipif(not CKPT.exists(), reason="s0 checkpoint not present")
@pytest.mark.parametrize("fixture", [TRIAD, EXTENDED], ids=["triad_cmaj", "extended_c9"])
def test_frontend_preserves_six_head_argmax(fixture):
    """`CCLFrontend` is the identity function on the precomputed hybrid_cqt
    feature (see ccl_frontend.py module docstring for the spike outcome:
    neither nnAudio (a) nor a baked librosa-basis conv (b) preserved
    argmax on all 6 heads, so the front-end input is the feature, not
    PCM). This test proves the identity seam is exact end-to-end: feeding
    the reference `hybrid_cqt` feature through `CCLFrontend` and then
    through the net reproduces `reference_probs`'s own per-frame,
    per-head argmax exactly, on both a plain triad (exercises the
    triad/bass/root heads) and an extended C9 chord (additionally
    exercises the 7th/9th/11th/13th "extension" heads, which predict
    "none" on a plain triad).
    """
    if not fixture.exists():
        pytest.skip(f"fixture not present: {fixture}")

    bundle = load_ccl()
    ref_probs = reference_probs(bundle.net, fixture, sample_rate=bundle.sample_rate)

    feature = _cqt_v2(fixture, bundle.sample_rate)
    fe = CCLFrontend().eval()
    with torch.no_grad():
        fed = fe(torch.tensor(feature, dtype=torch.float32))
        test_probs = bundle.net.inference(fed)

    assert len(test_probs) == 6
    for name, p_ref, p_test in zip(HEAD_NAMES, ref_probs, test_probs):
        n = min(p_ref.shape[0], p_test.shape[0])
        assert n > 50
        a_ref = np.argmax(p_ref[:n], axis=1)
        a_test = np.argmax(np.asarray(p_test)[:n], axis=1)
        agreement = float(np.mean(a_ref == a_test))
        assert agreement == 1.0, f"{name} head argmax agreement {agreement} != 1.0"


@pytest.mark.skipif(not CKPT.exists(), reason="s0 checkpoint not present")
def test_extended_fixture_activates_extension_heads():
    """Sanity check on the new `extended_c9.wav` fixture itself: unlike
    `triad_cmaj.wav` (a plain triad, which correctly predicts "none" on
    the 7th/9th/11th/13th heads), the C9 chord must actually drive at
    least one of those heads to a non-"none" (i.e. non-zero) argmax on
    at least one frame -- otherwise the fixture wouldn't be exercising
    what it's meant to.
    """
    bundle = load_ccl()
    probs = reference_probs(bundle.net, EXTENDED, sample_rate=bundle.sample_rate)
    extension_heads = probs[2:]  # seventh, ninth, eleventh, thirteenth
    activated = any(np.any(np.argmax(p, axis=1) != 0) for p in extension_heads)
    assert activated, "extended_c9.wav fixture does not activate any extension head"
