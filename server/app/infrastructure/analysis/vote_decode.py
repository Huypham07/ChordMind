from collections import Counter
from .chords import Chord
from .onnx_infer import Frame
from .manifest import ModelSpec

FALLBACK_FRAME_DUR = 2048 / 22050

def majority_filter(values: list[int], kernel_size: int) -> list[int]:
    kernel = 1 if kernel_size < 1 else kernel_size
    if kernel % 2 == 0:
        kernel += 1
    n = len(values)
    if kernel == 1 or n < kernel:
        return list(values)
    pad = kernel // 2
    def at(padded_idx: int) -> int:
        i = padded_idx - pad
        if i < 0: return values[0]
        if i >= n: return values[n - 1]
        return values[i]
    out = [0] * n
    for idx in range(n):
        counts = Counter(at(idx + w) for w in range(kernel))
        max_count = max(counts.values())
        candidates = sorted(k for k, c in counts.items() if c == max_count)
        center = values[idx]
        out[idx] = center if center in candidates else candidates[0]
    return out

def merge_short_chords(chords: list[Chord], min_dur: float) -> list[Chord]:
    out = list(chords)
    while len(out) > 1:
        shortest, shortest_dur = -1, min_dur
        for i, c in enumerate(out):
            d = c.end - c.start
            if d < shortest_dur:
                shortest, shortest_dur = i, d
        if shortest < 0:
            break
        prev = shortest - 1 if shortest > 0 else -1
        nxt = shortest + 1 if shortest < len(out) - 1 else -1
        if prev < 0:
            keep = nxt
        elif nxt < 0:
            keep = prev
        else:
            keep = nxt if (out[nxt].end - out[nxt].start) > (out[prev].end - out[prev].start) else prev
        s, k = out[shortest], out[keep]
        s_dur, k_dur = s.end - s.start, k.end - k.start
        conf = (k.confidence * k_dur + s.confidence * s_dur) / (k_dur + s_dur)
        out[keep] = Chord(k.chord, min(k.start, s.start), max(k.end, s.end), conf)
        del out[shortest]
        ki = keep - 1 if keep > shortest else keep
        for j in (ki + 1, ki - 1):
            if 0 <= j < len(out) and out[j].chord == out[ki].chord:
                lo, hi = (j, ki) if j < ki else (ki, j)
                a, b = out[lo], out[hi]
                a_dur, b_dur = a.end - a.start, b.end - b.start
                out[lo] = Chord(a.chord, a.start, b.end,
                                (a.confidence * a_dur + b.confidence * b_dur) / (a_dur + b_dur))
                del out[hi]
                break
    return out

def vote_decode(frames: list[Frame], spec: ModelSpec,
                smoothing_kernel: int = 5, min_chord_dur: float = 0.5) -> list[Chord]:
    if not frames:
        return []
    labels = spec.labels
    smoothed = majority_filter([f.class_id for f in frames], smoothing_kernel)
    frame_dur = frames[1].time - frames[0].time if len(frames) > 1 else FALLBACK_FRAME_DUR
    chords: list[Chord] = []
    run_start = 0
    for i in range(1, len(frames) + 1):
        at_end = i == len(frames) or smoothed[i] != smoothed[run_start]
        if at_end:
            run = frames[run_start:i]
            conf = sum(f.confidence for f in run) / len(run)
            chords.append(Chord(labels[smoothed[run_start]], run[0].time,
                                run[-1].time + frame_dur, conf))
            run_start = i
    return merge_short_chords(chords, min_chord_dur)
