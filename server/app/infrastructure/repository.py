from sqlalchemy.orm import Session
from app.domain.entities import AnalysisResult
from app.domain.ports import SongRepository
from app.infrastructure.orm import SongRow

class SqlSongRepository(SongRepository):
    def __init__(self, session: Session):
        self._s = session

    def get(self, youtube_id: str) -> AnalysisResult | None:
        row = self._s.get(SongRow, youtube_id)
        return AnalysisResult.from_dict(row.analysis_json) if row else None

    def save(self, result: AnalysisResult) -> None:
        self._s.add(SongRow(
            id=result.source.youtubeId,
            youtube_id=result.source.youtubeId,
            title=result.source.title,
            analysis_json=result.to_dict(),
        ))
        self._s.commit()

    def recent(self, limit: int = 20) -> list[tuple[str, str]]:
        rows = self._s.query(SongRow).order_by(SongRow.created_at.desc()).limit(limit).all()
        return [(r.youtube_id, r.title) for r in rows]
