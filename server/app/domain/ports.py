from abc import ABC, abstractmethod
from app.domain.entities import AnalysisResult


class ModelSlot(ABC):
    """Port for an analysis model. A0 has one stub impl; A1 adds real slots."""
    @abstractmethod
    def run(self, youtube_id: str, title: str, duration: float) -> AnalysisResult: ...

    def run_file(self, song_id: str, title: str, audio_path: str) -> AnalysisResult:
        raise NotImplementedError


class SongRepository(ABC):
    """Port for persistence. Implemented in infrastructure; faked in use-case tests."""
    @abstractmethod
    def get(self, youtube_id: str) -> AnalysisResult | None: ...
    @abstractmethod
    def save(self, result: AnalysisResult) -> None: ...
    @abstractmethod
    def recent(self, limit: int = 20) -> list[tuple[str, str]]: ...
