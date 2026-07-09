"""Onset envelope / tempo / Ellis DP beat tracking.

Mirrors app/lib/core/beat/{onset,tempo,beat_tracker}.dart.
"""
import math
from dataclasses import dataclass

import numpy as np

from .stft import stft_magnitude

ONSET_FPS = 22050 / 512


def onset_envelope(pcm: np.ndarray, n_fft: int = 2048, hop: int = 512) -> np.ndarray:
    """Spectral-flux onset envelope: positive magnitude increase per frame,
    max-normalized to [0, 1]. env[0] == 0 (no predecessor)."""
    mag = stft_magnitude(pcm, n_fft=n_fft, hop=hop)
    n = mag.shape[0]
    env = np.zeros(n)
    diff = mag[1:] - mag[:-1]
    env[1:] = np.clip(diff, 0, None).sum(axis=1)
    mx = env.max()
    if mx > 0:
        env = env / mx
    return env


def estimate_tempo(onset: np.ndarray, fps: float = ONSET_FPS, prior_bpm: float = 120.0) -> float:
    """Autocorrelation tempo estimate over 40-240 BPM, weighted by a
    log-normal prior (1 octave std) centred on prior_bpm."""
    n = len(onset)
    if n < 4:
        return 0.0
    min_lag = max(1, round(fps * 60 / 240))
    max_lag = min(n - 1, round(fps * 60 / 40))
    if max_lag <= min_lag:
        return 0.0
    best_bpm, best_score, std = 0.0, -math.inf, 1.0
    for lag in range(min_lag, max_lag + 1):
        ac = float(np.dot(onset[lag:], onset[:n - lag]))
        bpm = 60 * fps / lag
        z = math.log(bpm / prior_bpm) / math.log(2) / std
        score = ac * math.exp(-0.5 * z * z)
        if score > best_score:
            best_score, best_bpm = score, bpm
    return best_bpm if best_score > 0 else 0.0


@dataclass
class BeatResult:
    beats: list
    bpm: float


def _dp_beats(localscore, period, tightness=100.0):
    n = len(localscore)
    if n < 3 or period < 1:
        return []
    backlink = [-1] * n
    cumscore = [0.0] * n
    lo_off = round(-2 * period)
    hi_off = min(round(-period / 2), -1)
    for i in range(n):
        best_score, best_prev = -math.inf, -1
        for off in range(lo_off, hi_off + 1):
            j = i + off
            if j < 0:
                continue
            dev = math.log(-off / period)
            score = cumscore[j] - tightness * dev * dev
            if score > best_score:
                best_score, best_prev = score, j
        if best_prev < 0:
            cumscore[i], backlink[i] = localscore[i], -1
        else:
            cumscore[i], backlink[i] = localscore[i] + best_score, best_prev
    tail, tail_score = -1, -math.inf
    for i in range(max(0, n - round(period)), n):
        if cumscore[i] > tail_score:
            tail_score, tail = cumscore[i], i
    if tail < 0:
        return []
    beats, i = [], tail
    while i >= 0:
        beats.append(i)
        if backlink[i] < 0:
            break
        i = backlink[i]
    return list(reversed(beats))


def track_beats(pcm: np.ndarray, sr: float = 22050.0) -> BeatResult:
    assert sr == 22050, "onset pipeline assumes sr == 22050"
    onset = onset_envelope(pcm)
    bpm = estimate_tempo(onset)
    if bpm <= 0:
        return BeatResult([], 0.0)
    period = 60 * ONSET_FPS / bpm
    frames = _dp_beats(list(onset), period)
    if len(frames) < 2:
        return BeatResult([], 0.0)
    return BeatResult([f / ONSET_FPS for f in frames], bpm)
