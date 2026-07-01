from app.domain.entities import AnalysisResult
from app.domain.ports import ModelSlot, SongRepository


class AnalyzeSong:
    """Return cached analysis if present, else run the model slot and persist it."""

    def __init__(self, repo: SongRepository, slot: ModelSlot):
        self._repo = repo
        self._slot = slot

    def execute(self, youtube_id: str, title: str, duration: float) -> AnalysisResult:
        cached = self._repo.get(youtube_id)
        if cached:
            return cached
        result = self._slot.run(youtube_id, title, duration)
        self._repo.save(result)
        return result
