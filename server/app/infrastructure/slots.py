from app.domain.entities import AnalysisResult
from app.domain.ports import ModelSlot
from app.infrastructure.fixtures import build_fixture


class StubAnalysisSlot(ModelSlot):
    """A0 placeholder. Replace with real beat/chord/key/segment slots in A1."""
    def run(self, youtube_id: str, title: str, duration: float) -> AnalysisResult:
        return build_fixture(youtube_id, title, duration)
