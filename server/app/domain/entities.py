from __future__ import annotations
from dataclasses import dataclass, field, asdict


@dataclass
class Source:
    youtubeId: str
    title: str
    duration: float
    bpm: float
    timeSignature: int


@dataclass
class Beat:
    time: float
    beatNum: int


@dataclass
class Chord:
    chord: str
    start: float
    end: float
    confidence: float


@dataclass
class SyncChord:
    chord: str
    beatIndex: int


@dataclass
class Segment:
    label: str
    start: float
    end: float


@dataclass
class AnalysisResult:
    songId: str
    source: Source
    key: str
    beats: list[Beat] = field(default_factory=list)
    downbeats: list[float] = field(default_factory=list)
    chords: list[Chord] = field(default_factory=list)
    synchronizedChords: list[SyncChord] = field(default_factory=list)
    segments: list[Segment] = field(default_factory=list)
    melody: dict | None = None

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict) -> "AnalysisResult":
        return cls(
            songId=d["songId"],
            source=Source(**d["source"]),
            key=d["key"],
            beats=[Beat(**b) for b in d.get("beats", [])],
            downbeats=list(d.get("downbeats", [])),
            chords=[Chord(**c) for c in d.get("chords", [])],
            synchronizedChords=[SyncChord(**s) for s in d.get("synchronizedChords", [])],
            segments=[Segment(**s) for s in d.get("segments", [])],
            melody=d.get("melody"),
        )
