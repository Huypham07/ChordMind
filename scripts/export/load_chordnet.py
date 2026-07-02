"""Load the reference ChordNet 2E1D checkpoint (model + norm stats + vocab).

Wires the real reference helpers from `reference/ChordMini/src` rather than
reimplementing checkpoint parsing or architecture guessing. In particular,
the model architecture (layer counts, head counts, group size) is *inferred
from the checkpoint's state-dict shapes* via `_infer_chordnet`, because the
"2E1D" checkpoint does not use ChordNet's constructor defaults (e.g. its
n_group is 2, not the default 12) -- constructing with the defaults would
silently produce a shape/name mismatch that only a strict state-dict load
catches.
"""
import sys
from dataclasses import dataclass
from pathlib import Path

import torch

from scripts.export.config import REFERENCE_ROOT

sys.path.insert(0, str(REFERENCE_ROOT))

from src.models.chord_net import ChordNet  # noqa: E402
from src.models.common.checkpoint_loading import _infer_chordnet  # noqa: E402
from src.utils import extract_model_state_dict, load_checkpoint  # noqa: E402
from src.evaluation.utils.common import extract_norm_stats, extract_vocab  # noqa: E402


@dataclass
class ChordNetBundle:
    model: torch.nn.Module
    mean: float
    std: float
    idx_to_chord: dict


def load_chordnet(ckpt_path: Path) -> ChordNetBundle:
    ckpt_path = Path(ckpt_path)
    checkpoint = load_checkpoint(str(ckpt_path), device="cpu")
    if checkpoint is None:
        raise FileNotFoundError(f"Checkpoint not found or unreadable: {ckpt_path}")

    mean, std = extract_norm_stats(str(ckpt_path))
    idx_to_chord, _ = extract_vocab(str(ckpt_path))

    state_dict = extract_model_state_dict(checkpoint)
    architecture = _infer_chordnet(state_dict, checkpoint.get("config"))
    model = ChordNet(**architecture)

    result = model.load_state_dict(state_dict, strict=False)
    if result.missing_keys or result.unexpected_keys:
        raise RuntimeError(
            "ChordNet checkpoint did not load cleanly: "
            f"missing_keys={result.missing_keys!r} unexpected_keys={result.unexpected_keys!r}"
        )

    model.eval()
    return ChordNetBundle(
        model=model,
        mean=float(mean),
        std=float(std),
        idx_to_chord=idx_to_chord,
    )
