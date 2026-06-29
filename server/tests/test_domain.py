from app.domain.entities import AnalysisResult


def test_analysis_result_dict_roundtrip():
    data = {
        "songId": "s1",
        "source": {"youtubeId": "abc", "title": "T", "duration": 100.0, "bpm": 120.0, "timeSignature": 4},
        "key": "C major",
        "beats": [{"time": 0.5, "beatNum": 1}],
        "downbeats": [0.5],
        "chords": [{"chord": "C", "start": 0.5, "end": 2.0, "confidence": 0.9}],
        "synchronizedChords": [{"chord": "C", "beatIndex": 0}],
        "segments": [{"label": "intro", "start": 0.0, "end": 8.0}],
        "melody": None,
    }
    r = AnalysisResult.from_dict(data)
    assert r.synchronizedChords[0].chord == "C"
    assert r.source.youtubeId == "abc"
    assert r.to_dict() == data  # serialization preserves the wire contract exactly
