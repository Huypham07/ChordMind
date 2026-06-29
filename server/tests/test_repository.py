from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.infrastructure.db import Base
from app.infrastructure import orm  # noqa: F401  registers SongRow on Base
from app.infrastructure.repository import SqlSongRepository
from app.domain.entities import AnalysisResult, Source

def _repo():
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    return SqlSongRepository(sessionmaker(engine)())

def _result():
    return AnalysisResult(songId="abc", key="C major",
        source=Source(youtubeId="abc", title="T", duration=100.0, bpm=120.0, timeSignature=4))

def test_save_then_get_roundtrip():
    repo = _repo()
    assert repo.get("abc") is None
    repo.save(_result())
    got = repo.get("abc")
    assert got is not None and got.source.youtubeId == "abc" and got.key == "C major"

def test_recent_lists_saved():
    repo = _repo()
    repo.save(_result())
    assert repo.recent() == [("abc", "T")]
