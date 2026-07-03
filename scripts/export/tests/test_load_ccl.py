import numpy as np
import pytest
import torch

from scripts.export.config import CCL_REFERENCE_ROOT
from scripts.export.load_ccl import CHECKPOINT_STEM, load_ccl, reference_probs

CKPT = CCL_REFERENCE_ROOT / "cache_data" / f"{CHECKPOINT_STEM}.sdict"
FIXTURE = CCL_REFERENCE_ROOT.parents[1] / "scripts" / "export" / "tests" / "fixtures" / "triad_cmaj.wav"

HEAD_NAMES = ("triad", "bass", "seventh", "ninth", "eleventh", "thirteenth")
HEAD_SIZES = (73, 13, 4, 4, 3, 3)


@pytest.mark.skipif(not CKPT.exists(), reason="s0 checkpoint not present")
def test_load_ccl_net_is_eval_module():
    bundle = load_ccl()
    assert isinstance(bundle.net, torch.nn.Module)
    assert not bundle.net.training
    assert bundle.sample_rate == 22050


@pytest.mark.skipif(not CKPT.exists(), reason="s0 checkpoint not present")
@pytest.mark.skipif(not FIXTURE.exists(), reason="fixture wav not present")
def test_reference_probs_six_heads_non_degenerate():
    bundle = load_ccl()
    probs = reference_probs(bundle.net, FIXTURE, sample_rate=bundle.sample_rate)

    assert len(probs) == 6

    frame_counts = {p.shape[0] for p in probs}
    assert len(frame_counts) == 1, f"head frame counts disagree: {[p.shape for p in probs]}"
    n_frames = frame_counts.pop()
    assert n_frames > 50  # ~11s at hop_length=512, sr=22050 -> ~473 frames

    for prob, name, size in zip(probs, HEAD_NAMES, HEAD_SIZES):
        assert prob.shape == (n_frames, size), f"{name} head shape mismatch: {prob.shape}"
        # Each row is a valid softmax distribution.
        assert np.allclose(prob.sum(axis=1), 1.0, atol=1e-4)

    # Non-degenerate: the model actually predicts varying content across
    # frames for the harmonically-rich triad fixture, rather than collapsing
    # to a single constant class for the whole clip.
    triad_argmax = np.argmax(probs[0], axis=1)
    assert len(np.unique(triad_argmax)) > 1
