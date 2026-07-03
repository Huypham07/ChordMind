import subprocess, sys, pytest
from pathlib import Path
from scripts.export.config import REFERENCE_ROOT, ARTIFACTS_DIR

CKPT = REFERENCE_ROOT / "checkpoints" / "2e1d_model_best.pth"

@pytest.mark.skipif(not CKPT.exists(), reason="checkpoint absent")
def test_cli_produces_artifacts():
    r = subprocess.run([sys.executable, "-m", "scripts.export", "chordnet_2e1d"],
                       cwd=Path(__file__).resolve().parents[3], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert (ARTIFACTS_DIR / "chordnet_2e1d.onnx").exists()
    assert (ARTIFACTS_DIR / "manifest.json").exists()
