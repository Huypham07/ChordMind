"""Load the reference chord-cnn-lstm (ISMIR2019 large-voca) net and reproduce
its reference 6-head inference, outside the monolithic `chord_recognition.py`
script.

The reference lives in its own `mir`/`NetworkBehavior` framework
(`reference/chord-cnn-lstm-model/`). Its top-level modules have real,
unavoidable filesystem side effects at *import* time (e.g.
`train_eval_test_split.py` opens `data/all_1217.csv` with a path relative to
the process cwd), mirroring what
`reference/ChordMiniApp/python_backend/services/detectors/chord_cnn_lstm_detector.py`
does (`sys.path.insert` + `os.chdir` into the model dir before importing
`chord_recognition`). We reproduce that same pattern here, but scope the
`os.chdir` to just the import (via a context manager, restored in `finally`)
rather than leaving the process cwd mutated -- the reference's own
`NetworkInterface` checkpoint loading does not actually need cwd to be the
model dir, because `chord_recognition.py`'s own `MODEL_NAMES` are already
absolute paths (see `NetworkInterface.__init__` in
`reference/chord-cnn-lstm-model/mir/nn/train.py:60` -- `os.path.join` with an
absolute `save_name` component discards the leading `WORKING_PATH`/`load_path`
components, so an absolute `model_name` load is cwd-independent).

Once imported, the net itself (`ChordNet.inference`, in
`chordnet_ismir_naive.py:179`) operates directly on the CQT feature array (no
`entry`/`DataEntry` object needed), which is what makes it separable from the
rest of the framework for this spike.
"""
import contextlib
import os
import sys
from dataclasses import dataclass

import librosa
import numpy as np
import torch

from scripts.export.config import CCL_REFERENCE_ROOT

CHECKPOINT_STEM = (
    "joint_chord_net_ismir_naive_v1.0_reweight(0.0,10.0)_s0.best"
)


@contextlib.contextmanager
def _chdir(path):
    original = os.getcwd()
    os.chdir(str(path))
    try:
        yield
    finally:
        os.chdir(original)


def _import_reference():
    """Import the reference `chordnet_ismir_naive` module and
    `mir.nn.train.NetworkInterface`, matching the detector's own
    `sys.path.insert` + `os.chdir` load pattern. Safe to call repeatedly --
    Python caches the modules in `sys.modules` after the first import, so
    only the first call actually needs the `os.chdir` (subsequent calls are
    plain dict lookups), but we scope it every time for correctness.
    """
    root = str(CCL_REFERENCE_ROOT)
    if root not in sys.path:
        sys.path.insert(0, root)
    with _chdir(CCL_REFERENCE_ROOT):
        import chordnet_ismir_naive  # noqa: E402
        from mir.nn.train import NetworkInterface  # noqa: E402
    return chordnet_ismir_naive, NetworkInterface


@dataclass
class CCLBundle:
    net: torch.nn.Module
    sample_rate: int


def load_ccl() -> CCLBundle:
    """Load the s0 member of the chord-cnn-lstm 5-model ensemble (feasibility
    spike -- the full ensemble average is a later task). Mirrors
    `chord_recognition.py`'s own `MODEL_NAMES` construction: an absolute path
    join of `current_dir`, `'cache_data'`, and the checkpoint stem (the
    `.sdict` suffix is appended internally by `NetworkInterface`).
    """
    chordnet_ismir_naive, NetworkInterface = _import_reference()

    model_name = str(CCL_REFERENCE_ROOT / "cache_data" / CHECKPOINT_STEM)
    sdict_path = model_name + ".sdict"
    if not os.path.exists(sdict_path):
        raise FileNotFoundError(f"Checkpoint not found: {sdict_path}")

    interface = NetworkInterface(
        chordnet_ismir_naive.ChordNet(None), model_name, load_checkpoint=False
    )
    if not interface.finalized:
        raise RuntimeError(
            f"NetworkInterface failed to load checkpoint weights from "
            f"{sdict_path} (finalized=False after construction)."
        )

    net = interface.net
    net.eval()
    return CCLBundle(net=net, sample_rate=22050)


def _cqt_v2(wav_path, sample_rate: int) -> np.ndarray:
    """Reproduce `extractors/cqt.py:CQTV2.extract` verbatim: `hybrid_cqt`
    with 36 bins/octave, fmin=F#0, 288 bins, hop_length=512, magnitude,
    float32, transposed to [frames, bins].
    """
    music, _sr = librosa.load(str(wav_path), sr=sample_rate)
    result = librosa.core.hybrid_cqt(
        music,
        bins_per_octave=36,
        fmin=librosa.note_to_hz("F#0"),
        n_bins=288,
        tuning=None,
        hop_length=512,
    ).T
    return abs(result).astype(np.float32)


def reference_probs(net: torch.nn.Module, wav_path, sample_rate: int = 22050):
    """Reproduce reference `ChordNet.inference` exactly: reference
    `hybrid_cqt` feature extraction, then the net's own internal
    `x[:, SHIFT_HIGH*SHIFT_STEP : SHIFT_HIGH*SHIFT_STEP+SPEC_DIM]` sub-band
    slice (done inside `ChordNet.inference` itself), returning the 6 softmax
    head arrays: (triad/root, bass, 7th, 9th, 11th, 13th).
    """
    cqt = _cqt_v2(wav_path, sample_rate)
    x = torch.tensor(cqt, dtype=torch.float32)
    with torch.no_grad():
        return net.inference(x)
