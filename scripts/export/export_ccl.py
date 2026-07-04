"""Export chord-cnn-lstm (`chordnet_ismir_naive.ChordNet`, s0 member) to a
FEATURE-IN ONNX graph: precomputed 288-bin `hybrid_cqt` (CQTV2) feature in,
6 decomposition-head softmax probabilities out.

## Why feature-in, not PCM-in

Task 2 (`ccl_frontend.py`) proved `hybrid_cqt` cannot be baked into an
ONNX-exportable graph faithfully (signal-adaptive `tuning=None` estimation
+ the pseudo/full-CQT octave switch). The decision there was: the ONNX
graph starts at the already-computed 288-bin feature (which the app
computes natively on-device, per Plan B), not PCM. `CCLFrontend` is the
identity-on-feature stub that records that seam.

## The net's own internal slice

`ChordNet.inference` (`chordnet_ismir_naive.py:179`) does not feed the
full 288-bin feature to `feed`/`forward` -- it first takes a 252-bin
sub-band slice: `x[:, SHIFT_HIGH*SHIFT_STEP : SHIFT_HIGH*SHIFT_STEP+SPEC_DIM]`
with `SHIFT_HIGH=6, SHIFT_STEP=3, SPEC_DIM=252`, i.e. `x[:, 18:270]`. That
slice is reproduced here (`WrappedCCL.forward`) so the exported graph
matches `inference`'s behavior exactly, not just `forward`'s.

`ChordNet.forward` returns a tuple of 6 *raw* (pre-softmax) head tensors.
`inference` softmaxes each independently before returning. We softmax in
the graph too (rather than leaving raw logits) so ONNX outputs are
directly comparable to `reference_probs` -- argmax is unaffected either
way, but this avoids a footgun for any caller that reads raw probabilities
instead of argmax.
"""
from pathlib import Path

import torch

from scripts.export.ccl_frontend import CCLFrontend
from scripts.export.load_ccl import load_ccl

# ChordNet.inference's own sub-band slice constants (SHIFT_HIGH*SHIFT_STEP,
# SPEC_DIM), duplicated here rather than imported because importing
# chordnet_ismir_naive directly (outside `load_ccl`'s scoped `sys.path`/
# `os.chdir` import dance) would re-trigger its module-level filesystem
# side effects; see load_ccl.py's module docstring.
SLICE_START = 18  # SHIFT_HIGH * SHIFT_STEP = 6 * 3
SPEC_DIM = 252

HEAD_NAMES = ("triad", "bass", "seventh", "ninth", "eleventh", "thirteenth")


class WrappedCCL(torch.nn.Module):
    """Feature (`[frames, 288]`) in, 6 per-frame softmax head probability
    tensors out. Wraps `CCLFrontend` (identity-on-feature seam) + the net's
    internal `[18:270]` sub-band slice + the net itself + per-head softmax.
    """

    def __init__(self, frontend: torch.nn.Module, net: torch.nn.Module):
        super().__init__()
        self.frontend = frontend
        self.net = net

    def forward(self, feature: torch.Tensor):
        x = self.frontend(feature)
        x = x[:, SLICE_START : SLICE_START + SPEC_DIM]
        # -1 (not the traced frame count) keeps the reshape dynamic-shape
        # friendly under torch.onnx.export's tracer.
        x = x.view(1, -1, SPEC_DIM)
        heads = self.net(x)
        return tuple(torch.softmax(h, dim=1) for h in heads)


def export_ccl(out_path: Path) -> Path:
    bundle = load_ccl()
    wrapped = WrappedCCL(CCLFrontend(), bundle.net).eval()

    dummy = torch.zeros(64, 288)
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    dynamic_axes = {"feature": {0: "frames"}}
    for name in HEAD_NAMES:
        dynamic_axes[name] = {0: "frames"}

    torch.onnx.export(
        wrapped,
        dummy,
        str(out_path),
        input_names=["feature"],
        output_names=list(HEAD_NAMES),
        dynamic_axes=dynamic_axes,
        opset_version=17,
    )
    return out_path
