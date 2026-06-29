from app.application.analyze_song import AnalyzeSong
from app.domain.ports import SongRepository
from app.infrastructure.slots import StubAnalysisSlot


class FakeRepo(SongRepository):
    def __init__(self):
        self.store = {}
        self.saves = 0

    def get(self, yid):
        return self.store.get(yid)

    def save(self, r):
        self.saves += 1
        self.store[r.source.youtubeId] = r

    def recent(self, limit=20):
        return [(k, v.source.title) for k, v in self.store.items()]


def test_runs_then_caches():
    repo = FakeRepo()
    uc = AnalyzeSong(repo, StubAnalysisSlot())
    first = uc.execute("abc", "Demo", 120.0)
    assert first.source.youtubeId == "abc"
    assert repo.saves == 1
    second = uc.execute("abc", "Demo", 120.0)  # must hit cache, not save again
    assert repo.saves == 1
    assert second.songId == first.songId
