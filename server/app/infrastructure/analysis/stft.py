"""STFT magnitude, mirrors app/lib/core/hybrid_cqt.dart `stftMagnitude`."""
import numpy as np


def stft_magnitude(pcm: np.ndarray, n_fft: int = 2048, hop: int = 512) -> np.ndarray:
    """Hann (periodic) window, center=True zero-padding, rfft magnitude.

    Returns float array [n_frames, n_fft//2+1].
    """
    y = np.asarray(pcm, dtype=np.float64)
    w = 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(n_fft) / n_fft)

    pad = n_fft // 2
    padded = np.zeros(len(y) + 2 * pad, dtype=np.float64)
    padded[pad:pad + len(y)] = y

    n_frames = 1 + (len(padded) - n_fft) // hop
    out = np.empty((n_frames, n_fft // 2 + 1), dtype=np.float64)
    for t in range(n_frames):
        base = t * hop
        frame = padded[base:base + n_fft] * w
        spec = np.fft.rfft(frame)
        out[t] = np.sqrt(spec.real ** 2 + spec.imag ** 2)
    return out
