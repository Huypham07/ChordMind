# server/tests/test_api.py
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from app.main import app
from app.infrastructure.db import Base, get_session
from app.infrastructure import orm  # noqa: F401  registers SongRow
from app.infrastructure import youtube

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
    monkeypatch.setattr(youtube, "fetch_meta", lambda vid: ("Demo Song", 120.0))
    return TestClient(app)

def test_parse_video_id():
    assert youtube.parse_video_id("https://www.youtube.com/watch?v=abcdefghijk") == "abcdefghijk"
    assert youtube.parse_video_id("https://youtu.be/abcdefghijk") == "abcdefghijk"

def test_bad_url_returns_400(monkeypatch):
    c = _client(monkeypatch)
    r = c.post("/songs", json={"url": "not a youtube link"})
    assert r.status_code == 400

def test_cors_preflight_allowed(monkeypatch):
    # Flutter web sends an OPTIONS preflight before POST; it must not 405.
    c = _client(monkeypatch)
    r = c.options(
        "/songs",
        headers={
            "Origin": "http://localhost:1234",
            "Access-Control-Request-Method": "POST",
        },
    )
    assert r.status_code == 200
    assert r.headers["access-control-allow-origin"] == "*"

def test_submit_and_fetch(monkeypatch):
    c = _client(monkeypatch)
    r = c.post("/songs", json={"url": "https://youtu.be/abcdefghijk"})
    assert r.status_code == 200
    assert r.json()["source"]["youtubeId"] == "abcdefghijk"
    g = c.get("/songs/abcdefghijk")
    assert g.status_code == 200
    assert g.json()["key"] == "C major"
    assert c.get("/songs/missing0000").status_code == 404
