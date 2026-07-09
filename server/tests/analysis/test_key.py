from app.infrastructure.analysis.chords import Chord
from app.infrastructure.analysis.key import estimate_key, DEFAULT_KEY

def test_key_empty_is_default():
    assert estimate_key([]) == DEFAULT_KEY

def test_key_c_major_progression():
    prog = [("C",2.0),("F",1.0),("G",1.0),("C",2.0),("Am",1.0),("F",1.0),("G",1.0)]
    t = 0.0; chords = []
    for name, dur in prog:
        chords.append(Chord(name, t, t + dur, 0.9)); t += dur
    assert estimate_key(chords) == "C major"
