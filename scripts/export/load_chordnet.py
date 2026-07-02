"""Load the reference ChordNet 2E1D checkpoint (model + norm stats + vocab).

Wires the real reference helpers from `reference/ChordMini/src` rather than
reimplementing checkpoint parsing or architecture guessing. The model itself
is constructed via the reference's own production loading entry point,
`src.models.load_model(...)`, mirroring how
`reference/ChordMini/src/evaluation/test_labeled_audio.py` loads a checkpoint
for evaluation (see its `load_model(args.checkpoint, args.model_type,
config, device, args)` call). This means we inherit the reference's own
architecture inference (`_infer_chordnet`) and any config-driven overrides,
rather than duplicating that logic here with a partial reimplementation.
"""
from dataclasses import dataclass
from pathlib import Path

import torch

from scripts.export.config import REFERENCE_ROOT

import sys

sys.path.insert(0, str(REFERENCE_ROOT))

from src.models import load_model  # noqa: E402
from src.utils import HParams  # noqa: E402
from src.evaluation.utils.common import extract_norm_stats, extract_vocab  # noqa: E402

CONFIG_PATH = REFERENCE_ROOT / "config" / "ChordMini.yaml"


@dataclass
class ChordNetBundle:
    model: torch.nn.Module
    mean: float
    std: float
    idx_to_chord: dict


def load_chordnet(ckpt_path: Path) -> ChordNetBundle:
    ckpt_path = Path(ckpt_path)
    if not ckpt_path.exists():
        raise FileNotFoundError(f"Checkpoint not found or unreadable: {ckpt_path}")

    # Same config source and load path as test_labeled_audio.py's
    # `config = HParams.load(args.config)`.
    config = HParams.load(str(CONFIG_PATH))

    mean, std = extract_norm_stats(str(ckpt_path))
    idx_to_chord, _ = extract_vocab(str(ckpt_path))

    # Mirrors test_labeled_audio.py:273 --
    # `model, _, _ = load_model(args.checkpoint, args.model_type, config, device, args)`
    # with model_type='ChordNet' for the 2E1D checkpoint. `load_model` itself
    # infers the architecture from the state dict/config and performs the
    # state-dict load (falling back to strict=False only if a strict load
    # fails), so we trust its production load path rather than duplicating
    # the strict-check here.
    model, _, _ = load_model(str(ckpt_path), "ChordNet", config, "cpu", None)

    model.eval()
    return ChordNetBundle(
        model=model,
        mean=float(mean),
        std=float(std),
        idx_to_chord=idx_to_chord,
    )
