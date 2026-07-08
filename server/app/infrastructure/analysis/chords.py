from dataclasses import dataclass

@dataclass
class Chord:
    chord: str
    start: float
    end: float
    confidence: float
