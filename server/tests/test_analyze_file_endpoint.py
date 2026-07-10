import io, numpy as np, soundfile as sf
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from app.main import app
from app.infrastructure.db import Base, get_session
from app.infrastructure import orm  # noqa: F401  registers SongRow


def _wav_bytes():
    buf = io.BytesIO()
    sf.write(buf, np.zeros(22050 * 2, dtype="float32"), 22050, format="WAV")
    return buf.getvalue()


def _client(monkeypatch):
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        future=True,
    )
    Base.metadata.create_all(engine)
    Session = sessionmaker(engine, future=True)

    def _override():
        s = Session()
        try:
            yield s
        finally:
            s.close()

    monkeypatch.setitem(app.dependency_overrides, get_session, _override)
    return TestClient(app)


def test_analyze_file_returns_result(monkeypatch):
    client = _client(monkeypatch)
    r = client.post("/songs/analyze-file",
                    files={"file": ("t.wav", _wav_bytes(), "audio/wav")},
                    data={"title": "Test"})
    assert r.status_code == 200
    body = r.json()
    assert "chords" in body and "key" in body and body["source"]["timeSignature"] == 4
