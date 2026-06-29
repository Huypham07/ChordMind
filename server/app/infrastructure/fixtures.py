from app.domain.entities import AnalysisResult, Source, Beat, Chord, SyncChord, Segment

# A simple 8+ beat I–V–vi–IV loop in C, 2 beats per chord, 120 bpm.
PROGRESSION = ["C", "G", "Am", "F"]


def build_fixture(youtube_id: str, title: str, duration: float) -> AnalysisResult:
    bpm, beats_per_chord = 120.0, 2
    spb = 60.0 / bpm  # seconds per beat
    n_beats = max(8, int(duration / spb))
    beats = [Beat(time=round(i * spb, 3), beatNum=(i % 4) + 1) for i in range(n_beats)]
    downbeats = [b.time for b in beats if b.beatNum == 1]
    chords, sync = [], []
    for i in range(0, n_beats, beats_per_chord):
        name = PROGRESSION[(i // beats_per_chord) % len(PROGRESSION)]
        start = beats[i].time
        end = beats[min(i + beats_per_chord, n_beats - 1)].time
        chords.append(Chord(chord=name, start=start, end=end, confidence=0.95))
        sync.append(SyncChord(chord=name, beatIndex=i))
    return AnalysisResult(
        songId=youtube_id,
        source=Source(youtubeId=youtube_id, title=title, duration=duration, bpm=bpm, timeSignature=4),
        key="C major",
        beats=beats, downbeats=downbeats, chords=chords, synchronizedChords=sync,
        segments=[Segment(label="verse", start=0.0, end=duration)], melody=None,
    )
