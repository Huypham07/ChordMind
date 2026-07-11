import math
from dataclasses import dataclass
import numpy as np
import onnxruntime as ort
from .manifest import ModelSpec, onnx_path

@dataclass(frozen=True)
class Frame:
    frame_index: int
    class_id: int
    confidence: float
    time: float

_SESSIONS: dict[str, ort.InferenceSession] = {}

def _session(spec: ModelSpec) -> ort.InferenceSession:
    s = _SESSIONS.get(spec.name)
    if s is None:
        s = ort.InferenceSession(onnx_path(spec), providers=["CPUExecutionProvider"])
        _SESSIONS[spec.name] = s
    return s

def run_pcm(pcm: np.ndarray, spec: ModelSpec) -> list[Frame]:
    if spec.input != "pcm":
        raise ValueError(f"run_pcm requires pcm model, got {spec.input}")
    sess = _session(spec)
    in_name = sess.get_inputs()[0].name  # 'pcm'
    W = spec.window_samples
    total = len(pcm)
    out: list[Frame] = []
    if total == 0:
        return out
    frames_per_window = hop = frame_dur = None
    gidx = 0
    offset = 0
    while offset < total:
        copy_len = min(total - offset, W)
        window = np.zeros(W, dtype="float32")
        window[:copy_len] = pcm[offset:offset + copy_len]
        logits = sess.run(None, {in_name: window[None, :]})[0][0]  # [frames, classes]
        if frames_per_window is None:
            frames_per_window = logits.shape[0]
            hop = W // (frames_per_window - 1)
            frame_dur = hop / spec.fs
        if copy_len < W:
            real = min(frames_per_window, max(0, math.ceil(copy_len / hop)))
        else:
            real = frames_per_window
        for f in range(real):
            row = logits[f]
            cid = int(np.argmax(row))
            m = float(row[cid])
            conf = 1.0 / float(np.sum(np.exp(row - m)))
            out.append(Frame(gidx, cid, conf, gidx * frame_dur))
            gidx += 1
        offset += W
    return out
