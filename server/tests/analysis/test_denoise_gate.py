"""Regression gate: denoise stays clean on a real clip.

Decodes the first 30s of the in-repo BTC reference clip and asserts the
default beat-sync path has no flicker / no sub-0.5s junk, and the vote
fallback path (at the new 0.5 default) has no sub-0.5s junk. Skips when
btc.onnx is absent (conftest guard) or the mp3 can't be decoded.
"""
from pathlib import Path
import pytest

from app.infrastructure.analysis.manifest import load_spec
from app.infrastructure.analysis.audio_io import decode_pcm
from app.infrastructure.analysis.onnx_infer import run_pcm
from app.infrastructure.analysis.beat import track_beats
from app.infrastructure.analysis.beat_sync import beat_sync_chords
from app.infrastructure.analysis.vote_decode import vote_decode
from app.infrastructure.analysis.noise_metrics import short_fraction, flicker_per_min

CLIP = Path(__file__).resolve().parents[3] / "reference" / "BTC-ISMIR19" / "test" / "example.mp3"


def _pcm_30s(spec):
    if not CLIP.exists():
        pytest.skip(f"reference clip not found: {CLIP}")
    try:
        full = decode_pcm(str(CLIP), spec.fs)
    except Exception as e:
        pytest.skip(f"cannot decode {CLIP.name}: {e}")
    return full[: spec.fs * 30]


def test_beatsync_path_is_clean_on_real_clip():
    spec = load_spec("btc")
    pcm = _pcm_30s(spec)
    dur = len(pcm) / spec.fs
    frames = run_pcm(pcm, spec)
    br = track_beats(pcm, sr=float(spec.fs))
    assert br.beats, "expected the tracker to find beats on this clip"
    d = sorted(br.beats[i] - br.beats[i - 1] for i in range(1, len(br.beats)))
    min_dur = 1.4 * d[len(d) // 2]
    chords = beat_sync_chords(frames, br.beats, spec, min_chord_dur=min_dur)
    assert flicker_per_min(chords, dur) == 0.0
    assert short_fraction(chords) == 0.0


def test_vote_fallback_has_no_short_junk_at_default():
    spec = load_spec("btc")
    pcm = _pcm_30s(spec)
    frames = run_pcm(pcm, spec)
    chords = vote_decode(frames, spec)  # default min_chord_dur now 0.5
    assert short_fraction(chords) == 0.0
