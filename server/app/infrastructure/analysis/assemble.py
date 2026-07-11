import numpy as np
from .manifest import ModelSpec
from .onnx_infer import run_pcm
from .beat import track_beats
from .vote_decode import vote_decode
from .beat_sync import beat_sync_chords
from .key import estimate_key

PLACEHOLDER_BPM = 120.0
PLACEHOLDER_TS = 4
MIN_CHORD_BEATS = 1.4

def _median_beat_spacing(beats: list[float]) -> float:
    if len(beats) < 2:
        return 0.0
    d = sorted(beats[i] - beats[i-1] for i in range(1, len(beats)))
    return d[len(d)//2]

def analyze_pcm(pcm: np.ndarray, song_id: str, title: str, spec: ModelSpec) -> dict:
    frames = run_pcm(pcm, spec)
    try:
        beat_res = track_beats(pcm, sr=float(spec.fs))
    except Exception:
        from .beat import BeatResult
        beat_res = BeatResult([], 0.0)
    beat_times = beat_res.beats
    if not beat_times:
        chords = vote_decode(frames, spec)
    else:
        min_dur = MIN_CHORD_BEATS * _median_beat_spacing(beat_times)
        chords = beat_sync_chords(frames, beat_times, spec, min_chord_dur=min_dur)
    key = estimate_key(chords)
    duration = len(pcm) / spec.fs
    bpm = PLACEHOLDER_BPM if not beat_times else beat_res.bpm

    beats = []
    downbeats = []
    if not beat_times:
        interval = 60.0 / PLACEHOLDER_BPM
        beat_num = 1
        t = 0.0
        while t < duration:
            beats.append({"time": t, "beatNum": beat_num})
            if beat_num == 1: downbeats.append(t)
            beat_num = beat_num % PLACEHOLDER_TS + 1
            t += interval
    else:
        for i, bt in enumerate(beat_times):
            beat_num = i % PLACEHOLDER_TS + 1
            beats.append({"time": bt, "beatNum": beat_num})
            if beat_num == 1: downbeats.append(bt)

    def chord_at(t: float) -> str:
        if not chords: return "N"
        for c in chords:
            if c.start <= t < c.end: return c.chord
        if t < chords[0].start: return chords[0].chord
        return chords[-1].chord

    sync = []
    prev = None
    for i, b in enumerate(beats):
        ch = chord_at(b["time"])
        if ch != prev:
            sync.append({"chord": ch, "beatIndex": i})
            prev = ch

    return {
        "songId": song_id,
        "source": {"youtubeId": song_id, "title": title or song_id,
                   "duration": float(duration), "bpm": float(bpm), "timeSignature": PLACEHOLDER_TS},
        "key": key,
        "beats": beats,
        "downbeats": downbeats,
        "chords": [{"chord": c.chord, "start": float(c.start), "end": float(c.end),
                    "confidence": float(c.confidence)} for c in chords],
        "synchronizedChords": sync,
        "segments": [],
        "melody": None,
    }
