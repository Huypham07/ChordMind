"""Regenerate the deterministic golden fixture for the analysis-pipeline
regression gate.

Generates a fixed C-major-triad tone (deterministic, no external audio), runs
the Python pipeline, and writes the clip + golden JSON. Run from server/:

    python -m tests.fixtures.make_golden

NOTE: this is a Python-pipeline regression snapshot, NOT a Dart<->Python
parity check. True cross-language parity requires running the Flutter
OnDeviceAnalyzer (rootBundle assets + onnxruntime plugin) on the same clip;
that is deferred to a Flutter-harness run. The per-stage unit tests already
validate the Dart->Python transcription.
"""
import json
from pathlib import Path
import numpy as np
import soundfile as sf

from app.infrastructure.analysis.manifest import load_spec
from app.infrastructure.analysis.assemble import analyze_pcm

FIX = Path(__file__).resolve().parent
FS = 22050
DUR_S = 12.0


def make_clip() -> np.ndarray:
    """Deterministic C-major triad (C4/E4/G4) with a 2 Hz amplitude pulse so
    the onset/beat tracker has something periodic to lock onto."""
    t = np.arange(int(FS * DUR_S)) / FS
    freqs = [261.63, 329.63, 392.00]  # C4, E4, G4
    tone = sum(np.sin(2 * np.pi * f * t) for f in freqs) / len(freqs)
    pulse = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 2.0 * t))  # 2 Hz on/off
    return (tone * pulse * 0.3).astype("float32")


def main() -> None:
    clip = make_clip()
    sf.write(FIX / "golden_clip.wav", clip, FS)
    spec = load_spec("btc")
    result = analyze_pcm(clip, "golden", "Golden", spec)
    (FIX / "golden_btc.json").write_text(json.dumps(result, indent=2))
    print(f"wrote golden_clip.wav ({len(clip)} samples) + golden_btc.json "
          f"({len(result['chords'])} chords, key={result['key']})")


if __name__ == "__main__":
    main()
