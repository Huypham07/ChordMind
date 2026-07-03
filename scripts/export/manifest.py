import hashlib
import json
from pathlib import Path
from scripts.export.config import FEATURE
from scripts.export.load_chordnet import load_bundle


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
