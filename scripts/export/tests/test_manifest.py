import json
import pytest
from pathlib import Path
from scripts.export.manifest import write_manifest_entry
from scripts.export.config import REFERENCE_ROOT, FEATURE

CKPT = REFERENCE_ROOT / "checkpoints" / "2e1d_model_best.pth"


@pytest.mark.skipif(not CKPT.exists(), reason="checkpoint absent")
def test_entry_has_170_labels(tmp_path):
    onnx = tmp_path / "m.onnx"
    onnx.write_bytes(b"stub")
    manifest = tmp_path / "manifest.json"
    e = write_manifest_entry(
        onnx, CKPT, name="chordnet_2e1d", step="chord", decode="vote", manifest_path=manifest
    )
    assert len(e["labels"]) == 170
    assert e["step"] == "chord" and e["seq_len"] == 108
    assert json.loads(manifest.read_text())["chordnet_2e1d"]["sha256"] == e["sha256"]
    assert e["window_samples"] == (FEATURE.seq_len - 1) * FEATURE.hop_length
