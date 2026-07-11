import numpy as np, soundfile as sf

def decode_pcm(path: str, fs: int) -> np.ndarray:
    try:
        data, sr = sf.read(path, dtype="float32", always_2d=True)
    except Exception:
        import audioread
        with audioread.audio_open(path) as f:
            sr = f.samplerate
            buf = b"".join(f.read_data())
        data = np.frombuffer(buf, dtype="<i2").astype("float32") / 32768.0
        data = data.reshape(-1, f.channels)
    mono = data.mean(axis=1)                    # downmix
    if sr != fs:                                 # linear resample (parity-neutral)
        n = int(round(len(mono) * fs / sr))
        mono = np.interp(np.linspace(0, len(mono) - 1, n),
                         np.arange(len(mono)), mono).astype("float32")
    return np.ascontiguousarray(mono, dtype="float32")
