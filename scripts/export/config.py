from dataclasses import dataclass
from pathlib import Path

@dataclass(frozen=True)
class FeatureConfig:
    n_bins: int
    bins_per_octave: int
    hop_length: int
    sample_rate: int
    n_classes: int
    seq_len: int

FEATURE = FeatureConfig(144, 24, 2048, 22050, 170, 108)
REFERENCE_ROOT = Path(__file__).resolve().parents[2] / "reference" / "ChordMini"
CCL_REFERENCE_ROOT = Path(__file__).resolve().parents[2] / "reference" / "chord-cnn-lstm-model"
ARTIFACTS_DIR = Path(__file__).resolve().parents[2] / "artifacts" / "onnx"
