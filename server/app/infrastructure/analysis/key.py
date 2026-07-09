import math
from .chords import Chord

_NOTE_NAMES = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
_PC_BY_LETTER = {"C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11}
_QUALITY = {
    "":[0,4,7], "maj":[0,4,7], "min":[0,3,7], "m":[0,3,7], "dim":[0,3,6],
    "aug":[0,4,8], "7":[0,4,7,10], "maj7":[0,4,7,11], "min7":[0,3,7,10],
    "m7":[0,3,7,10], "dim7":[0,3,6,9], "hdim7":[0,3,6,10], "m7b5":[0,3,6,10],
    "sus2":[0,2,7], "sus4":[0,5,7],
}
_MAJOR = [6.35,2.23,3.48,2.33,4.38,4.09,2.52,5.19,2.39,3.66,2.29,2.88]
_MINOR = [6.33,2.68,3.52,5.38,2.60,3.53,2.54,4.75,3.98,2.69,3.34,3.17]
DEFAULT_KEY = "C major"

def _parse_root(note: str):
    if not note: return None
    base = _PC_BY_LETTER.get(note[0].upper())
    if base is None: return None
    pc = base
    for c in note[1:]:
        if c == "#": pc += 1
        elif c == "b": pc -= 1
    return pc % 12

def _chord_pcs(label: str):
    if label in ("N","X") or not label: return None
    without_bass = label.split("/")[0]
    parts = without_bass.split(":")
    root = _parse_root(parts[0])
    if root is None: return None
    quality = parts[1] if len(parts) > 1 else ""
    intervals = _QUALITY.get(quality, _QUALITY["maj"])
    return {(root + iv) % 12 for iv in intervals}

def _pearson(a, b):
    n = len(a)
    ma, mb = sum(a)/n, sum(b)/n
    num = sum((a[i]-ma)*(b[i]-mb) for i in range(n))
    den = math.sqrt(sum((x-ma)**2 for x in a) * sum((x-mb)**2 for x in b))
    return num/den if den else 0.0

def _rotate(profile, tonic):
    return [profile[(i - tonic) % 12] for i in range(12)]

def estimate_key(chords: list[Chord]) -> str:
    hist = [0.0]*12
    any_weight = False
    for ch in chords:
        pcs = _chord_pcs(ch.chord)
        if pcs is None: continue
        w = ch.end - ch.start
        if w <= 0: continue
        for pc in pcs: hist[pc] += w
        any_weight = True
    if not any_weight: return DEFAULT_KEY
    best_score, best_tonic, best_major = -math.inf, 0, True
    for tonic in range(12):
        s = _pearson(hist, _rotate(_MAJOR, tonic))
        if s > best_score: best_score, best_tonic, best_major = s, tonic, True
        s = _pearson(hist, _rotate(_MINOR, tonic))
        if s > best_score: best_score, best_tonic, best_major = s, tonic, False
    return f"{_NOTE_NAMES[best_tonic]} {'major' if best_major else 'minor'}"
