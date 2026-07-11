from app.infrastructure.analysis.onnx_infer import Frame
from app.infrastructure.analysis.manifest import load_spec
from app.infrastructure.analysis.beat_sync import beat_sync_chords


def _frames(seq, dt=0.1):
    return [Frame(i, c, 1.0, i * dt) for i, c in enumerate(seq)]


def test_beat_sync_one_chord_per_beat_interval_merged():
    spec = load_spec("btc")
    # class ids: use indices whose labels are distinct; 0 and 1
    frames = _frames([0]*10 + [1]*10)  # 2s of class0 then class1
    beats = [0.0, 1.0, 2.0]
    out = beat_sync_chords(frames, beats, spec)
    assert len(out) == 2
    assert out[0].chord == spec.labels[0] and out[1].chord == spec.labels[1]
