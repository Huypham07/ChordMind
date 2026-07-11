import numpy as np
from app.infrastructure.analysis.beat import onset_envelope, estimate_tempo, track_beats, ONSET_FPS


def test_onset_first_frame_zero_and_normalized():
    pcm = np.random.default_rng(0).standard_normal(22050).astype("float32")
    env = onset_envelope(pcm)
    assert env[0] == 0.0 and env.max() <= 1.0 + 1e-9


def test_tempo_on_click_train_near_120():
    fs, bpm = 22050, 120.0
    pcm = np.zeros(fs * 4, dtype="float32")
    step = int(fs * 60 / bpm)
    pcm[::step] = 1.0
    est = estimate_tempo(onset_envelope(pcm))
    assert abs(est - 120) < 12  # within ~10%


def test_track_beats_returns_ascending_times():
    fs, bpm = 22050, 120.0
    pcm = np.zeros(fs * 4, dtype="float32")
    pcm[::int(fs * 60 / bpm)] = 1.0
    res = track_beats(pcm)
    assert len(res.beats) >= 4
    assert all(b2 > b1 for b1, b2 in zip(res.beats, res.beats[1:]))
