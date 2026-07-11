import numpy as np
from app.infrastructure.analysis.manifest import load_spec
from app.infrastructure.analysis.onnx_infer import run_pcm

def test_run_pcm_frames_monotonic_and_typed():
    spec = load_spec("btc")
    pcm = np.zeros(spec.window_samples + 5000, dtype="float32")  # ~2 windows
    frames = run_pcm(pcm, spec)
    assert frames, "no frames"
    assert [f.frame_index for f in frames] == list(range(len(frames)))
    assert all(0 <= f.class_id < len(spec.labels) for f in frames)
    assert all(0.0 <= f.confidence <= 1.0 for f in frames)
    # time strictly increasing by a constant frame_dur ~ 2048/22050
    d = frames[1].time - frames[0].time
    assert abs(d - 2048/22050) < 1e-6
