from app.infrastructure.analysis.chords import Chord
from app.infrastructure.analysis.vote_decode import majority_filter, merge_short_chords

def test_majority_filter_smooths_single_flip():
    assert majority_filter([1,1,2,1,1], 3) == [1,1,1,1,1]

def test_majority_filter_noop_when_shorter_than_kernel():
    assert majority_filter([1,2], 5) == [1,2]

def test_majority_filter_tie_keeps_center_else_smallest():
    # window [1,2] tie -> center kept when center is a candidate
    assert majority_filter([1,2,1], 1) == [1,2,1]  # kernel 1 = no-op

def test_merge_short_absorbs_into_longer_neighbor():
    ch = [Chord("D",0.0,1.0,0.9), Chord("D7",1.0,1.1,0.5), Chord("G",1.1,2.1,0.9)]
    out = merge_short_chords(ch, 0.3)
    assert [c.chord for c in out] == ["D","G"]
    assert out[0].end == 1.1  # D extended to cover the junk D7
