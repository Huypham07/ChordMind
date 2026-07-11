import numpy as np, soundfile as sf
from app.infrastructure.analysis.manifest import load_spec
from app.infrastructure.analysis.audio_io import decode_pcm

def test_load_spec_btc():
    s = load_spec("btc")
    assert s.fs == 22050 and s.window_samples == 219136
    assert len(s.labels) == 170 and s.input == "pcm" and s.decode == "vote"

def test_decode_pcm_mono_float32(tmp_path):
    p = tmp_path / "t.wav"
    sf.write(p, np.zeros(44100, dtype="float32"), 44100)  # 1s @ 44.1k
    pcm = decode_pcm(str(p), 22050)
    assert pcm.dtype == np.float32 and pcm.ndim == 1
    assert abs(len(pcm) - 22050) <= 2  # resampled to ~1s @ 22050
