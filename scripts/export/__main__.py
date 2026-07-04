import sys
from pathlib import Path

import onnxruntime as ort

from scripts.export.config import REFERENCE_ROOT, ARTIFACTS_DIR
from scripts.export.export_ccl import HEAD_NAMES, export_ccl
from scripts.export.export_chordnet import export_model
from scripts.export.parity_check import argmax_agreement, ccl_head_agreement, max_logit_diff
from scripts.export.manifest import write_ccl_manifest_entry, write_manifest_entry

MODELS = {
    "chordnet_2e1d": ("checkpoints/2e1d_model_best.pth", "chord", "vote", "ChordNet"),
    "btc": ("checkpoints/btc_model_best.pth", "chord", "vote", "BTC"),
}

FIXTURES_DIR = Path(__file__).parent / "tests" / "fixtures"


def _main_ccl() -> int:
    onnx = export_ccl(ARTIFACTS_DIR / "chord_cnn_lstm.onnx")

    clips = sorted(FIXTURES_DIR.glob("*.wav"))
    if not clips:
        print(f"PARITY FAIL: no fixture clips found in {FIXTURES_DIR}")
        return 1

    for wav in clips:
        agreements = ccl_head_agreement(onnx, wav)
        print(f"{wav.name}: head_agreement={dict(zip(HEAD_NAMES, agreements))}")
        for head_name, agreement in zip(HEAD_NAMES, agreements):
            if agreement < 0.99:
                print(f"PARITY FAIL {wav.name} [{head_name}]: agreement={agreement}")
                return 1

    sess = ort.InferenceSession(str(onnx))
    head_dims = [o.shape[-1] for o in sess.get_outputs()]

    write_ccl_manifest_entry(
        onnx, head_dims=head_dims, manifest_path=ARTIFACTS_DIR / "manifest.json",
    )
    print("OK chord_cnn_lstm")
    return 0


def main(name: str) -> int:
    if name == "chord_cnn_lstm":
        return _main_ccl()

    rel, step, decode, model_type = MODELS[name]
    ckpt = REFERENCE_ROOT / rel
    onnx = export_model(ckpt, ARTIFACTS_DIR / f"{name}.onnx", model_type)

    clips = sorted(FIXTURES_DIR.glob("*.wav"))
    if not clips:
        print(f"PARITY FAIL: no fixture clips found in {FIXTURES_DIR}")
        return 1

    for wav in clips[:3]:
        agreement = argmax_agreement(onnx, ckpt, wav, model_type)
        diff = max_logit_diff(onnx, ckpt, wav, model_type)
        print(f"{wav.name}: argmax_agreement={agreement} max_logit_diff={diff}")
        if agreement < 1.0:
            print(f"PARITY FAIL {wav.name}: argmax_agreement={agreement}")
            return 1

    write_manifest_entry(onnx, ckpt, name=name, step=step, decode=decode,
                         manifest_path=ARTIFACTS_DIR / "manifest.json",
                         model_type=model_type)
    print(f"OK {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
