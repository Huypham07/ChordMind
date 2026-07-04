from pathlib import Path
import torch
from scripts.export.cqt_frontend import CQTFrontend
from scripts.export.load_chordnet import load_bundle
from scripts.export.config import FEATURE


class WrappedChordNet(torch.nn.Module):
    """PCM in, chord-logits out: front-end CQT + model, single fixed
    108-frame window (both ChordNet's and BTC's positional encodings are
    fixed to seq_len, so neither is a variable-length model). Model-agnostic
    despite the name: `forward` already handles both a `(logits, features)`
    tuple (ChordNet) and a bare logits tensor (BTC)."""

    def __init__(self, frontend, model):
        super().__init__()
        self.frontend = frontend
        self.model = model

    def forward(self, pcm):
        feat = self.frontend(pcm)  # [1, 108, 144]
        out = self.model(feat)  # (logits, features) for ChordNet, logits for BTC
        return out[0] if isinstance(out, tuple) else out


def export_model(ckpt_path: Path, out_path: Path, model_type: str) -> Path:
    b = load_bundle(ckpt_path, model_type)
    wrapped = WrappedChordNet(CQTFrontend(b.mean, b.std), b.model).eval()

    # NOTE: with center=True CQT framing (librosa/nnAudio default), N PCM
    # samples yield 1 + N // hop_length frames. seq_len * hop_length would
    # therefore yield seq_len + 1 = 109 frames -- one too many for
    # ChordNet's fixed seq_len=108 positional encoding. The sample count
    # that yields exactly seq_len frames is (seq_len - 1) * hop_length.
    n = (FEATURE.seq_len - 1) * FEATURE.hop_length
    dummy = torch.zeros(1, n)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        wrapped,
        dummy,
        str(out_path),
        input_names=["pcm"],
        output_names=["logits"],
        dynamic_axes={"pcm": {1: "samples"}},
        opset_version=17,
    )
    return out_path


def export_chordnet(ckpt_path: Path, out_path: Path) -> Path:
    return export_model(ckpt_path, out_path, "ChordNet")


def export_btc(ckpt_path: Path, out_path: Path) -> Path:
    return export_model(ckpt_path, out_path, "BTC")
