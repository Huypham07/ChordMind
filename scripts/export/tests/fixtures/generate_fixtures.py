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
    # Harmonically rich sustained C major triad: C4/E4/G4 fundamentals
    # (261.63/329.63/392.00 Hz), each with 5 harmonics at amplitude 1/h,
    # plus light fixed-seed noise. Pure sine tones are out-of-distribution
    # for chord models trained on real instrument timbre -- nnAudio's CQT
    # magnitude diverges slightly from librosa's on such unrealistic input,
    # which previously flipped BTC's argmax from 'C' to 'N' (no-chord)
    # between the reference and ONNX paths. Real-ish harmonic content with
    # noise keeps both ChordNet and BTC at argmax_agreement == 1.0.
    fundamentals = (261.63, 329.63, 392.00)  # C4, E4, G4
    n_harmonics = 5
    tone = np.zeros_like(t)
    for f0 in fundamentals:
        for h in range(1, n_harmonics + 1):
            tone += (1.0 / h) * np.sin(2 * np.pi * f0 * h * t)
    noise = 0.02 * np.random.RandomState(0).randn(t.shape[0])
    signal = tone + noise
    signal = signal / np.max(np.abs(signal))
    return 0.2 * signal


def make_extended_c9(t: np.ndarray) -> np.ndarray:
    # Harmonically rich C9 chord (root C, major 3rd E, 5th G, minor 7th Bb,
    # 9th D): C3/E3/G3/Bb3/D4 (130.81/164.81/196.00/233.08/293.66 Hz), each
    # with 5 harmonics at amplitude 1/h, plus light fixed-seed (1) Gaussian
    # noise, normalized -- same recipe as make_triad, but including the
    # flat-7th and 9th scale degrees so the chord-cnn-lstm net's 7th/9th
    # decomposition heads (which predict "none" on a plain triad) also
    # activate on this fixture.
    fundamentals = (130.81, 164.81, 196.00, 233.08, 293.66)  # C3 E3 G3 Bb3 D4
    n_harmonics = 5
    tone = np.zeros_like(t)
    for f0 in fundamentals:
        for h in range(1, n_harmonics + 1):
            tone += (1.0 / h) * np.sin(2 * np.pi * f0 * h * t)
    noise = 0.02 * np.random.RandomState(1).randn(t.shape[0])
    signal = tone + noise
    signal = signal / np.max(np.abs(signal))
    return 0.2 * signal


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
    _write("extended_c9.wav", make_extended_c9(t))
    _write("white_noise.wav", make_noise(n_samples))
    _write("sweep_100_2000hz.wav", make_sweep(t))


if __name__ == "__main__":
    main()
