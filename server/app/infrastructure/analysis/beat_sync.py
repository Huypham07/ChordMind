from collections import defaultdict
from .chords import Chord
from .onnx_infer import Frame
from .manifest import ModelSpec
from .vote_decode import majority_filter, merge_short_chords, FALLBACK_FRAME_DUR


def beat_sync_chords(frames: list[Frame], beat_times: list[float], spec: ModelSpec,
                     beat_smoothing_kernel: int = 3, min_chord_dur: float = 0.0) -> list[Chord]:
    if not frames or not beat_times:
        return []
    labels = spec.labels
    n_index = labels.index("N") if "N" in labels else -1
    frame_dur = frames[1].time - frames[0].time if len(frames) > 1 else FALLBACK_FRAME_DUR
    song_end = frames[-1].time + frame_dur

    bounds: list[float] = []
    if beat_times[0] > 0:
        bounds.append(0.0)
    bounds.extend(beat_times)
    end = song_end if song_end > bounds[-1] else bounds[-1] + frame_dur
    bounds.append(end)

    winners: list[int] = []
    confs: list[float] = []
    fi = 0
    prev_class = -1
    for b in range(len(bounds) - 1):
        lo, hi = bounds[b], bounds[b + 1]
        counts: dict[int, int] = defaultdict(int)
        conf_sum: dict[int, float] = defaultdict(float)
        while fi < len(frames) and frames[fi].time < hi:
            if frames[fi].time >= lo:
                c = frames[fi].class_id
                counts[c] += 1
                conf_sum[c] += frames[fi].confidence
            fi += 1
        if not counts:
            winner = prev_class if prev_class >= 0 else (n_index if n_index >= 0 else 0)
            conf = 0.0
        else:
            winner = next(iter(counts))
            for c in counts:
                if counts[c] > counts[winner] or (counts[c] == counts[winner] and conf_sum[c] > conf_sum[winner]):
                    winner = c
            conf = conf_sum[winner] / counts[winner]
        prev_class = winner
        winners.append(winner)
        confs.append(conf)

    smoothed = majority_filter(winners, beat_smoothing_kernel)

    segments: list[Chord] = []
    for b in range(len(smoothed)):
        lo, hi = bounds[b], bounds[b + 1]
        label = labels[smoothed[b]]
        conf = confs[b]
        if segments and segments[-1].chord == label:
            prev = segments.pop()
            prev_dur = prev.end - prev.start
            cur_dur = hi - lo
            segments.append(Chord(prev.chord, prev.start, hi,
                                  (prev.confidence * prev_dur + conf * cur_dur) / (prev_dur + cur_dur)))
        else:
            segments.append(Chord(label, lo, hi, conf))

    return merge_short_chords(segments, min_chord_dur) if min_chord_dur > 0 else segments
