import hashlib
import json
from pathlib import Path
from scripts.export.config import FEATURE
from scripts.export.load_chordnet import load_bundle

CCL_HEAD_NAMES = ("triad", "bass", "seventh", "ninth", "eleventh", "thirteenth")


def _sha256(p: Path) -> str:
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def write_manifest_entry(
    onnx_path, ckpt_path, *, name, step, decode, manifest_path, version="1",
    model_type="ChordNet",
) -> dict:
    b = load_bundle(Path(ckpt_path), model_type)
    labels = [b.idx_to_chord[i] for i in range(len(b.idx_to_chord))]
    entry = {
        "name": name,
        "step": step,
        "file": Path(onnx_path).name,
        "sha256": _sha256(onnx_path),
        "version": version,
        "fs": FEATURE.sample_rate,
        "seq_len": FEATURE.seq_len,
        "n_classes": FEATURE.n_classes,
        "labels": labels,
        "decode": decode,
        "window_samples": (FEATURE.seq_len - 1) * FEATURE.hop_length,
        "opset": 17,
    }
    mp = Path(manifest_path)
    data = json.loads(mp.read_text()) if mp.exists() else {}
    data[name] = entry
    mp.write_text(json.dumps(data, indent=2))
    return entry


def write_ccl_manifest_entry(
    onnx_path, *, head_dims, manifest_path, name="chord_cnn_lstm", version="1",
) -> dict:
    """Feature-in manifest entry for chord-cnn-lstm -- a DIFFERENT schema
    than `write_manifest_entry`'s flat-170-label ChordNet/BTC entries: no
    `idx_to_chord` labels (there is no single flat class space), instead a
    `heads` list describing the 6 decomposition heads (triad/bass/seventh/
    ninth/eleventh/thirteenth) plus the `feature` recipe the app needs to
    reproduce the `hybrid_cqt` (CQTV2) front-end natively on-device, since
    the exported graph is feature-in (see `export_ccl.py`), not PCM-in.
    """
    if len(head_dims) != len(CCL_HEAD_NAMES):
        raise ValueError(
            f"expected {len(CCL_HEAD_NAMES)} head dims, got {len(head_dims)}"
        )
    entry = {
        "name": name,
        "step": "chord",
        "model": "chord-cnn-lstm",
        "input": "cqtv2_feature",
        "decode": "xhmm",
        "file": Path(onnx_path).name,
        "sha256": _sha256(onnx_path),
        "version": version,
        "opset": 17,
        "sample_rate": 22050,
        "feature": {
            "type": "hybrid_cqt",
            "sr": 22050,
            "hop_length": 512,
            "n_bins": 288,
            "bins_per_octave": 36,
            "fmin": "F#0",
            "tuning": None,
            "magnitude": True,
        },
        "heads": [
            {"name": head_name, "dim": int(dim)}
            for head_name, dim in zip(CCL_HEAD_NAMES, head_dims)
        ],
    }
    mp = Path(manifest_path)
    data = json.loads(mp.read_text()) if mp.exists() else {}
    data[name] = entry
    mp.write_text(json.dumps(data, indent=2))
    return entry
