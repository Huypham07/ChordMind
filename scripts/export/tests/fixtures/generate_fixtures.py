"""Generate the deterministic synthetic parity-test fixture clips.

Run once with `scripts/export/.venv/bin/python -m
scripts.export.tests.fixtures.generate_fixtures` from the repo root to
(re)write the .wav files in this directory. The resulting clips are small
and are committed to the repo so the parity test has no runtime
dependency on this generator.

See README.md in this directory for what each clip is and why.
"""
import numpy as np
import soundfile as sf
from pathlib import Path

SR = 22050
# Must exceed the ONNX front-end's fixed 108-frame window --
# (108 - 1) * 2048 / 22050 = 9.94 s -- so that the reference librosa path
# (which extracts features from the file's actual, unpadded duration) sees
# the same 108 real (non-zero-padded) frames as the ONNX path. A shorter
# clip would force the ONNX side to zero-pad while the reference side
# naturally produces fewer than 108 frames, comparing non-aligned windows.
DURATION_S = 11.0
OUT_DIR = Path(__file__).parent


def _write(name: str, samples: np.ndarray) -> None:
    samples = np.clip(samples, -1.0, 1.0).astype(np.float32)
    sf.write(str(OUT_DIR / name), samples, SR, subtype="PCM_16")


def make_triad(t: np.ndarray) -> np.ndarray:
    # Sustained C major triad: C4 (261.63 Hz), E4 (329.63 Hz), G4 (392.00 Hz).
    tone = (
        np.sin(2 * np.pi * 261.63 * t)
        + np.sin(2 * np.pi * 329.63 * t)
        + np.sin(2 * np.pi * 392.00 * t)
    )
    return 0.2 * tone / 3.0


def make_noise(n_samples: int) -> np.ndarray:
    rng = np.random.default_rng(seed=42)
    return 0.05 * rng.standard_normal(n_samples)


def make_sweep(t: np.ndarray) -> np.ndarray:
    # Linear frequency sweep from 100 Hz to 2000 Hz over the clip duration.
    f0, f1 = 100.0, 2000.0
    k = (f1 - f0) / DURATION_S
    phase = 2 * np.pi * (f0 * t + 0.5 * k * t ** 2)
    return 0.3 * np.sin(phase)


def main() -> None:
    n_samples = int(SR * DURATION_S)
    t = np.arange(n_samples) / SR

    _write("triad_cmaj.wav", make_triad(t))
    _write("white_noise.wav", make_noise(n_samples))
    _write("sweep_100_2000hz.wav", make_sweep(t))


if __name__ == "__main__":
    main()
