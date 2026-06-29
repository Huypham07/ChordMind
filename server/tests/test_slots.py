from app.infrastructure.slots import StubAnalysisSlot


def test_stub_slot_returns_valid_analysis():
    r = StubAnalysisSlot().run("abc", "Demo", 120.0)
    assert r.source.youtubeId == "abc"
    assert len(r.synchronizedChords) > 0
    assert max(c.beatIndex for c in r.synchronizedChords) < len(r.beats)
