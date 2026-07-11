"""Ground-truth-free noise metrics over a decoded chord timeline.

short_fraction: how much of the timeline is sub-threshold junk.
flicker_per_min: A->B->A flips where B is a short segment (almost always error).
"""
from .chords import Chord


def short_fraction(chords: list[Chord], thresh: float = 0.5) -> float:
    if not chords:
        return 0.0
    short = sum(1 for c in chords if c.end - c.start < thresh)
    return short / len(chords)


def flicker_per_min(chords: list[Chord], duration: float, thresh: float = 0.5) -> float:
    if duration <= 0:
        return 0.0
    n = len(chords)
    flick = sum(
        1 for i in range(1, n - 1)
        if chords[i - 1].chord == chords[i + 1].chord
        and (chords[i].end - chords[i].start) < thresh
    )
    return flick / (duration / 60.0)
