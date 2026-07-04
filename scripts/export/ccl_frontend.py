"""chord-cnn-lstm front-end: 288-bin `hybrid_cqt` feature -> net input.

## Feasibility spike result: option (c) -- feature input, not PCM

`reference/chord-cnn-lstm-model/extractors/cqt.py:44` computes the feature
as `librosa.core.hybrid_cqt(music, bins_per_octave=36,
fmin=librosa.note_to_hz('F#0'), n_bins=288, tuning=None, hop_length=512)`.
This spike evaluated whether that feature can be baked into an
ONNX-exportable graph closely enough to preserve the net's per-frame,
per-head argmax (the parity bar for this plan). It cannot, for two
independent reasons discovered empirically:

1. **`tuning=None` is signal-adaptive.** `hybrid_cqt` calls
   `librosa.estimate_tuning(y, sr, bins_per_octave)` on the actual input
   audio and shifts `fmin` by the estimated fractional-bin offset before
   building filters. This is not a fixed graph parameter -- it is a
   full pitch-histogram estimation pass over the raw audio, executed
   *before* the CQT itself. Baking a fixed `tuning=0` (as any
   filter-bank/conv approach must, absent a second baked estimation
   stage) already introduces a data-dependent, per-clip frequency offset
   relative to the reference.

2. **`hybrid_cqt` is intrinsically two different algorithms stitched
   together** (`pseudo_cqt`, an FFT/STFT-domain approximation, for the
   upper octaves where the analysis window fits within `2*hop_length`;
   full recursive-downsampling `cqt` -- using librosa's internal
   multi-rate filterbank + `soxr_hq` polyphase resampling -- for the
   lower octaves), switching bin-by-bin based on filter length. There is
   no single closed-form kernel/conv that reproduces both branches
   without re-implementing librosa's resampling internals bit-for-bit.

**Evidence tried, in the order the plan specifies:**

- **(a) nnAudio CQT**, both `CQT1992v2` (direct time-domain convolution,
  closest analog to `pseudo_cqt`/full CQT without downsampling) and
  `CQT2010v2` (recursive downsampling, closest analog to librosa's own
  low-octave algorithm), each with `norm={1,2}` and `pad_mode=
  {constant,reflect}`, and with `fmin` shifted by the fixture's own
  `librosa.estimate_tuning(...)` offset to remove reason (1) above as a
  variable: **best result was CQT2010v2, tuned fmin, pad_mode=constant,
  triad head 99.37% and bass head 99.58% per-frame argmax agreement**
  against `reference_probs` on `triad_cmaj.wav` (474 frames; the 4
  extension heads were already 100%, since they only distinguish a
  handful of coarse classes and are far less sensitive to these small
  magnitude perturbations). Every nnAudio variant tried plateaued in the
  99.0-99.6% range -- never 100% -- with mismatches concentrated at
  chord-onset/clip-boundary frames where the two algorithms' magnitude
  estimates cross a decision boundary between two near-tied classes.
- **(b) Baking librosa's own basis as a fixed conv/matmul**: a
  first-principles attempt using `librosa.filters.constant_q(...)`
  (the same complex Morlet-style kernels librosa itself builds
  internally) applied via direct time-domain convolution at the
  fixture's native rate landed at only 2-100% per-head agreement
  (worse than nnAudio on the fundamental-sensitive triad/bass heads),
  because getting the normalization/scaling convention and the
  `pseudo_cqt`/full-`cqt` octave switch bit-compatible with librosa's
  internal recursive/resampling algorithm is itself a from-scratch
  reimplementation of a nontrivial part of librosa's C-adjacent
  numerics (`soxr_hq` resampling in particular) -- out of scope for a
  spike, and not guaranteed to reach exact match even with more time,
  since a from-scratch resampler will not bit-match `soxr_hq`.

**Decision:** per the plan's Task 2 Step 1/4, this is an acceptable
spike outcome, not a failure. `CCLFrontend` below is the identity
function on an already-computed `hybrid_cqt` feature array (shape
`[.., 288]`) rather than a PCM-in front-end. The actual `hybrid_cqt`
computation must run natively on-device (e.g. a native CQT
implementation via FFI, or a precomputed-feature ingestion path) -- see
Task 3, which must export starting at the feature input, and the
manifest, which must record `input: "cqtv2_feature"` (not `"pcm"`).
"""
import torch


class CCLFrontend(torch.nn.Module):
    """Identity pass-through on a precomputed `hybrid_cqt` feature.

    `forward(feature) -> feature` unchanged, `[.., 288]` in, `[.., 288]`
    out. This exists (rather than removing the front-end module
    entirely) so `export_ccl` (Task 3) has a single, documented seam to
    wrap in the ONNX graph -- the graph's real input is the 288-bin
    feature, and this module records that decision in code, not just in
    a comment on `export_ccl`.
    """

    N_BINS = 288

    def forward(self, feature: torch.Tensor) -> torch.Tensor:
        if feature.shape[-1] != self.N_BINS:
            raise ValueError(
                f"CCLFrontend expects a precomputed hybrid_cqt feature with "
                f"{self.N_BINS} bins in the last dimension (see module "
                f"docstring for why PCM input is not supported), got shape "
                f"{tuple(feature.shape)}."
            )
        return feature
