from app.infrastructure.analysis.chords import Chord
from app.infrastructure.analysis.noise_metrics import short_fraction, flicker_per_min

def test_short_fraction_counts_sub_threshold():
    ch = [Chord("C", 0.0, 1.0, 0.9), Chord("G", 1.0, 1.2, 0.9)]  # 0.2s short
    assert short_fraction(ch) == 0.5
    assert short_fraction([]) == 0.0

def test_flicker_counts_sandwiched_short_segment():
    # C [long] G [0.2s short] C [long] -> one flicker (G between two C)
    ch = [Chord("C", 0.0, 1.0, 0.9), Chord("G", 1.0, 1.2, 0.9), Chord("C", 1.2, 2.2, 0.9)]
    assert flicker_per_min(ch, duration=60.0) == 1.0

def test_flicker_ignores_long_sandwiched_segment():
    # G is 1s (>=0.5) -> not a flicker even though neighbors match
    ch = [Chord("C", 0.0, 1.0, 0.9), Chord("G", 1.0, 2.0, 0.9), Chord("C", 2.0, 3.0, 0.9)]
    assert flicker_per_min(ch, duration=60.0) == 0.0
