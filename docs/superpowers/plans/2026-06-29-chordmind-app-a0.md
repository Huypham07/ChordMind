# ChordMind App A0 — Core Vertical Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A running, demoable ChordMind vertical: paste a YouTube link → server returns a (stubbed) `AnalysisResult` → Flutter app shows a synced chord grid, guitar/piano diagrams, lyrics, and a fresh light/dark theme.

**Architecture:** Clean Architecture. Server layers `domain` (framework-free entities + ports) → `application` (use cases on ports) → `infrastructure` (SQLAlchemy repo, stub ModelSlot, yt-dlp) → `api` (FastAPI + DTOs); dependencies point inward only. Model slots are **stubs returning fixtures**. Flutter app (mobile-first, web as the dev/test surface) consumes the frozen `AnalysisResult` JSON contract through a repository over a REST client.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2.x, Pydantic v2, Postgres 16 (Docker), pytest. Flutter 3.x (Dart 3), Riverpod, dio, youtube_player_iframe, flutter_test.

## Global Constraints

- Audio input source: **YouTube link only** for A0.
- `AnalysisResult` JSON shape is **frozen** — defined by the server domain entity (Task 2), mirrored by the Dart models (Task 8); server and app must match field-for-field. No app/UI code reads model internals.
- **Clean Architecture:** dependencies point inward (api → application → domain; infrastructure → domain). `domain` imports no framework. Use cases depend on ports (`ModelSlot`, `SongRepository`), never on concrete SQLAlchemy/FastAPI types. Apply pragmatically — only ports that earn their keep; no one-impl interfaces beyond those two.
- All model work is **stub**: slots return hand-authored fixtures; never call a real model.
- Mobile-first layout; Flutter **web** must build and run (it is the verification surface).
- DB: **Postgres** via `docker-compose` for local dev.
- Theme: fresh ChordMind identity, **light + dark**, tokens defined once in `core/theme`.
- TDD: every task writes a failing test first. Commit after each task.
- Deferred to later plans (do NOT build here): A1 real ModelSlot variety, A2 WebRTC/Ableton sync, A3 versioning/voting. `reharm`/`band`/`versions` are **placeholder tabs only**.

---

### Task 1: Server scaffold + Postgres + health endpoint

**Files:**
- Create: `server/pyproject.toml`
- Create: `server/docker-compose.yml`
- Create: `server/app/main.py`
- Create: `server/app/config.py`
- Test: `server/tests/test_health.py`

**Interfaces:**
- Produces: FastAPI `app` in `server/app/main.py`; `GET /health` → `{"status": "ok"}`. Settings object `get_settings()` with `database_url`.

- [ ] **Step 1: Write the failing test**

```python
# server/tests/test_health.py
from fastapi.testclient import TestClient
from app.main import app

def test_health():
    client = TestClient(app)
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && python -m pytest tests/test_health.py -v`
Expected: FAIL (ModuleNotFoundError: app.main)

- [ ] **Step 3: Write scaffold + minimal app**

```toml
# server/pyproject.toml
[project]
name = "chordmind-server"
version = "0.0.0"
requires-python = ">=3.12"
dependencies = [
  "fastapi", "uvicorn[standard]", "sqlalchemy>=2", "psycopg[binary]",
  "pydantic>=2", "pydantic-settings", "yt-dlp",
]
[project.optional-dependencies]
dev = ["pytest", "httpx"]

[tool.pytest.ini_options]
pythonpath = ["."]
```

```python
# server/app/config.py
from pydantic_settings import BaseSettings
from functools import lru_cache

class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg://chordmind:chordmind@localhost:5432/chordmind"

@lru_cache
def get_settings() -> Settings:
    return Settings()
```

```python
# server/app/main.py
from fastapi import FastAPI

app = FastAPI(title="ChordMind")

@app.get("/health")
def health():
    return {"status": "ok"}
```

```yaml
# server/docker-compose.yml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: chordmind
      POSTGRES_PASSWORD: chordmind
      POSTGRES_DB: chordmind
    ports: ["5432:5432"]
    volumes: ["pgdata:/var/lib/postgresql/data"]
volumes:
  pgdata:
```

- [ ] **Step 4: Install deps and run test**

Run: `cd server && pip install -e ".[dev]" && python -m pytest tests/test_health.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/ && git commit -m "feat(server): scaffold FastAPI + postgres compose + health"
```

---

### Task 2: Domain layer — entities + ports

**Layer:** `domain/` (innermost; framework-free, no FastAPI/SQLAlchemy/Pydantic imports).

**Files:**
- Create: `server/app/domain/__init__.py`
- Create: `server/app/domain/entities.py`
- Create: `server/app/domain/ports.py`
- Test: `server/tests/test_domain.py`

**Interfaces:**
- Produces: dataclasses `Source`, `Beat`, `Chord`, `SyncChord`, `Segment`, `AnalysisResult` with `to_dict()` and `from_dict(d)`. Field names are the **frozen wire contract** the Dart models (Task 8) mirror: `AnalysisResult(songId, source, key, beats, downbeats, chords, synchronizedChords, segments, melody)`, `Source(youtubeId, title, duration, bpm, timeSignature)`, `SyncChord(chord, beatIndex)`.
- Produces ports (ABCs): `ModelSlot.run(youtube_id, title, duration) -> AnalysisResult`; `SongRepository.get(youtube_id) -> AnalysisResult | None`, `.save(result) -> None`, `.recent(limit=20) -> list[tuple[str, str]]`.

- [ ] **Step 1: Write the failing test**

```python
# server/tests/test_domain.py
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && .venv/bin/python -m pytest tests/test_domain.py -v`
Expected: FAIL (cannot import app.domain.entities)

- [ ] **Step 3: Write entities + ports**

```python
# server/app/domain/__init__.py
```

```python
# server/app/domain/entities.py
from __future__ import annotations
from dataclasses import dataclass, field, asdict

@dataclass
class Source:
    youtubeId: str
    title: str
    duration: float
    bpm: float
    timeSignature: int

@dataclass
class Beat:
    time: float
    beatNum: int

@dataclass
class Chord:
    chord: str
    start: float
    end: float
    confidence: float

@dataclass
class SyncChord:
    chord: str
    beatIndex: int

@dataclass
class Segment:
    label: str
    start: float
    end: float

@dataclass
class AnalysisResult:
    songId: str
    source: Source
    key: str
    beats: list[Beat] = field(default_factory=list)
    downbeats: list[float] = field(default_factory=list)
    chords: list[Chord] = field(default_factory=list)
    synchronizedChords: list[SyncChord] = field(default_factory=list)
    segments: list[Segment] = field(default_factory=list)
    melody: dict | None = None

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict) -> "AnalysisResult":
        return cls(
            songId=d["songId"],
            source=Source(**d["source"]),
            key=d["key"],
            beats=[Beat(**b) for b in d.get("beats", [])],
            downbeats=list(d.get("downbeats", [])),
            chords=[Chord(**c) for c in d.get("chords", [])],
            synchronizedChords=[SyncChord(**s) for s in d.get("synchronizedChords", [])],
            segments=[Segment(**s) for s in d.get("segments", [])],
            melody=d.get("melody"),
        )
```

```python
# server/app/domain/ports.py
from abc import ABC, abstractmethod
from app.domain.entities import AnalysisResult

class ModelSlot(ABC):
    """Port for an analysis model. A0 has one stub impl; A1 adds real slots."""
    @abstractmethod
    def run(self, youtube_id: str, title: str, duration: float) -> AnalysisResult: ...

class SongRepository(ABC):
    """Port for persistence. Implemented in infrastructure; faked in use-case tests."""
    @abstractmethod
    def get(self, youtube_id: str) -> AnalysisResult | None: ...
    @abstractmethod
    def save(self, result: AnalysisResult) -> None: ...
    @abstractmethod
    def recent(self, limit: int = 20) -> list[tuple[str, str]]: ...
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && .venv/bin/python -m pytest tests/test_domain.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/ && git commit -m "feat(server): domain entities + ports (clean arch core)"
```

---

### Task 3: Infrastructure — persistence (db + ORM + repository)

**Layer:** `infrastructure/` (implements the `SongRepository` port using SQLAlchemy/Postgres).

**Files:**
- Create: `server/app/infrastructure/__init__.py`
- Create: `server/app/infrastructure/db.py`
- Create: `server/app/infrastructure/orm.py`
- Create: `server/app/infrastructure/repository.py`
- Test: `server/tests/test_repository.py`

**Interfaces:**
- Consumes: `AnalysisResult` (Task 2), `SongRepository` port (Task 2), `get_settings()` (Task 1).
- Produces: `Base`, `get_session()` (FastAPI dependency yielding a `Session`), `init_db()`. ORM `SongRow(id, youtube_id, title, analysis_json, created_at)`. `SqlSongRepository(session)` implementing the `SongRepository` port; stores `result.to_dict()` as JSON, keyed by `result.source.youtubeId`.
- (Tables `versions`/`votes`/`users` are deferred to A3 — do NOT create them.)

- [ ] **Step 1: Write the failing test** (in-memory SQLite)

```python
# server/tests/test_repository.py
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && .venv/bin/python -m pytest tests/test_repository.py -v`
Expected: FAIL (cannot import app.infrastructure.db)

- [ ] **Step 3: Write db + orm + repository**

```python
# server/app/infrastructure/__init__.py
```

```python
# server/app/infrastructure/db.py
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from app.config import get_settings

Base = declarative_base()
_engine = create_engine(get_settings().database_url, future=True)
SessionLocal = sessionmaker(bind=_engine, future=True)

def init_db():
    from app.infrastructure import orm  # noqa: F401  ensure tables are registered
    Base.metadata.create_all(_engine)

def get_session():
    with SessionLocal() as s:
        yield s
```

```python
# server/app/infrastructure/orm.py
from datetime import datetime
from sqlalchemy import String, DateTime, JSON
from sqlalchemy.orm import Mapped, mapped_column
from app.infrastructure.db import Base

class SongRow(Base):
    __tablename__ = "songs"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    youtube_id: Mapped[str] = mapped_column(String, index=True)
    title: Mapped[str] = mapped_column(String)
    analysis_json: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
```

```python
# server/app/infrastructure/repository.py
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && .venv/bin/python -m pytest tests/test_repository.py -v`
Expected: PASS (both tests)

- [ ] **Step 5: Commit**

```bash
git add server/ && git commit -m "feat(server): SQLAlchemy SongRepository (infrastructure)"
```

---

### Task 4: Infrastructure — stub ModelSlot + fixtures

**Layer:** `infrastructure/` (implements the `ModelSlot` port with hand-authored fixtures — the A0 placeholder for real models).

**Files:**
- Create: `server/app/infrastructure/fixtures.py`
- Create: `server/app/infrastructure/slots.py`
- Test: `server/tests/test_slots.py`

**Interfaces:**
- Consumes: `AnalysisResult` and friends (Task 2), `ModelSlot` port (Task 2).
- Produces: `build_fixture(youtube_id, title, duration) -> AnalysisResult`; `StubAnalysisSlot` implementing `ModelSlot`. Fixture = I–V–vi–IV loop in C, 120 bpm, 2 beats/chord; every `SyncChord.beatIndex` references a real beat.

- [ ] **Step 1: Write the failing test**

```python
# server/tests/test_slots.py
from app.infrastructure.slots import StubAnalysisSlot

def test_stub_slot_returns_valid_analysis():
    r = StubAnalysisSlot().run("abc", "Demo", 120.0)
    assert r.source.youtubeId == "abc"
    assert len(r.synchronizedChords) > 0
    assert max(c.beatIndex for c in r.synchronizedChords) < len(r.beats)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && .venv/bin/python -m pytest tests/test_slots.py -v`
Expected: FAIL (cannot import)

- [ ] **Step 3: Write fixtures + slot**

```python
# server/app/infrastructure/fixtures.py
from app.domain.entities import AnalysisResult, Source, Beat, Chord, SyncChord, Segment

# A simple 8+ beat I–V–vi–IV loop in C, 2 beats per chord, 120 bpm.
PROGRESSION = ["C", "G", "Am", "F"]

def build_fixture(youtube_id: str, title: str, duration: float) -> AnalysisResult:
    bpm, beats_per_chord = 120.0, 2
    spb = 60.0 / bpm  # seconds per beat
    n_beats = max(8, int(duration / spb))
    beats = [Beat(time=round(i * spb, 3), beatNum=(i % 4) + 1) for i in range(n_beats)]
    downbeats = [b.time for b in beats if b.beatNum == 1]
    chords, sync = [], []
    for i in range(0, n_beats, beats_per_chord):
        name = PROGRESSION[(i // beats_per_chord) % len(PROGRESSION)]
        start = beats[i].time
        end = beats[min(i + beats_per_chord, n_beats - 1)].time
        chords.append(Chord(chord=name, start=start, end=end, confidence=0.95))
        sync.append(SyncChord(chord=name, beatIndex=i))
    return AnalysisResult(
        songId=youtube_id,
        source=Source(youtubeId=youtube_id, title=title, duration=duration, bpm=bpm, timeSignature=4),
        key="C major",
        beats=beats, downbeats=downbeats, chords=chords, synchronizedChords=sync,
        segments=[Segment(label="verse", start=0.0, end=duration)], melody=None,
    )
```

```python
# server/app/infrastructure/slots.py
from app.domain.entities import AnalysisResult
from app.domain.ports import ModelSlot
from app.infrastructure.fixtures import build_fixture

class StubAnalysisSlot(ModelSlot):
    """A0 placeholder. Replace with real beat/chord/key/segment slots in A1."""
    def run(self, youtube_id: str, title: str, duration: float) -> AnalysisResult:
        return build_fixture(youtube_id, title, duration)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && .venv/bin/python -m pytest tests/test_slots.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/ && git commit -m "feat(server): stub ModelSlot + fixtures (infrastructure)"
```

---

### Task 5: Application — AnalyzeSong use case

**Layer:** `application/` (orchestrates ports; no framework, no DB imports — depends only on `domain`).

**Files:**
- Create: `server/app/application/__init__.py`
- Create: `server/app/application/analyze_song.py`
- Test: `server/tests/test_analyze_song.py`

**Interfaces:**
- Consumes: `SongRepository` + `ModelSlot` ports (Task 2), `StubAnalysisSlot` (Task 4, used only in the test).
- Produces: `AnalyzeSong(repo: SongRepository, slot: ModelSlot)` with `execute(youtube_id, title, duration) -> AnalysisResult`: returns cached result if the repo has it; otherwise runs the slot, saves, returns. This is the replacement for the old `ml_worker.analyze_song`.

- [ ] **Step 1: Write the failing test** (in-memory fake repo — no DB needed, the clean-arch payoff)

```python
# server/tests/test_analyze_song.py
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && .venv/bin/python -m pytest tests/test_analyze_song.py -v`
Expected: FAIL (cannot import AnalyzeSong)

- [ ] **Step 3: Write the use case**

```python
# server/app/application/__init__.py
```

```python
# server/app/application/analyze_song.py
from app.domain.entities import AnalysisResult
from app.domain.ports import ModelSlot, SongRepository

# ponytail: synchronous use case; if the real pipeline gets slow, push execute() onto a job queue.
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && .venv/bin/python -m pytest tests/test_analyze_song.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/ && git commit -m "feat(server): AnalyzeSong use case (application)"
```

---

### Task 6: API layer — DTO, DI wiring, routes, YouTube helper

**Layer:** `api/` (FastAPI adapters) + one infrastructure helper. Wires everything via dependency injection.

**Files:**
- Create: `server/app/api/__init__.py`
- Create: `server/app/api/schemas.py`
- Create: `server/app/api/deps.py`
- Create: `server/app/api/routes.py`
- Create: `server/app/infrastructure/youtube.py`
- Modify: `server/app/main.py` (replace Task 1 body: mount router + init_db on startup)
- Test: `server/tests/test_api.py`

**Interfaces:**
- Consumes: `AnalyzeSong` (Task 5), `SqlSongRepository`, `get_session`, `init_db` (Task 3), `StubAnalysisSlot` (Task 4).
- Produces:
  - `SubmitRequest(BaseModel)` with field `url: str` (input DTO).
  - `deps.py`: `get_repo(session) -> SqlSongRepository`, `get_analyze_song(session) -> AnalyzeSong` (DI factories).
  - `youtube.py`: `parse_video_id(url) -> str`, `fetch_meta(video_id) -> tuple[str, float]`.
  - Routes: `GET /health` → `{"status":"ok"}`; `POST /songs {url}` → AnalysisResult JSON; `GET /songs/{youtube_id}` → AnalysisResult JSON or 404; `GET /songs` → `[{youtubeId, title}]`.
- Note: the `/health` route now lives in `routes.py`; Task 1's `test_health.py` must still pass.

- [ ] **Step 1: Write the failing test**

```python
# server/tests/test_api.py
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.infrastructure.db import Base, get_session
from app.infrastructure import orm  # noqa: F401  registers SongRow
from app.infrastructure import youtube

def _client(monkeypatch):
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    Session = sessionmaker(engine)
    app.dependency_overrides[get_session] = lambda: (yield from [Session()])
    monkeypatch.setattr(youtube, "fetch_meta", lambda vid: ("Demo Song", 120.0))
    return TestClient(app)

def test_parse_video_id():
    assert youtube.parse_video_id("https://www.youtube.com/watch?v=abcdefghijk") == "abcdefghijk"
    assert youtube.parse_video_id("https://youtu.be/abcdefghijk") == "abcdefghijk"

def test_submit_and_fetch(monkeypatch):
    c = _client(monkeypatch)
    r = c.post("/songs", json={"url": "https://youtu.be/abcdefghijk"})
    assert r.status_code == 200
    assert r.json()["source"]["youtubeId"] == "abcdefghijk"
    g = c.get("/songs/abcdefghijk")
    assert g.status_code == 200
    assert g.json()["key"] == "C major"
    assert c.get("/songs/missing0000").status_code == 404
    app.dependency_overrides.clear()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && .venv/bin/python -m pytest tests/test_api.py -v`
Expected: FAIL (cannot import app.infrastructure.youtube / routes missing)

- [ ] **Step 3: Write DTO, deps, youtube, routes, main**

```python
# server/app/api/__init__.py
```

```python
# server/app/api/schemas.py
from pydantic import BaseModel

class SubmitRequest(BaseModel):
    url: str

# ponytail: the domain AnalysisResult IS the response contract (returned via to_dict);
# no duplicate Pydantic response model to keep in sync.
```

```python
# server/app/infrastructure/youtube.py
import re

_PATTERNS = [r"v=([\w-]{11})", r"youtu\.be/([\w-]{11})", r"([\w-]{11})$"]

def parse_video_id(url: str) -> str:
    for p in _PATTERNS:
        m = re.search(p, url)
        if m:
            return m.group(1)
    raise ValueError(f"cannot parse video id from {url!r}")

def fetch_meta(video_id: str) -> tuple[str, float]:
    # ponytail: real metadata via yt-dlp; falls back to stub if it fails (A0 analysis is stubbed anyway).
    try:
        import yt_dlp
        with yt_dlp.YoutubeDL({"quiet": True, "skip_download": True}) as ydl:
            info = ydl.extract_info(f"https://youtu.be/{video_id}", download=False)
            return info.get("title", video_id), float(info.get("duration", 120.0))
    except Exception:
        return video_id, 120.0
```

```python
# server/app/api/deps.py
from fastapi import Depends
from sqlalchemy.orm import Session
from app.infrastructure.db import get_session
from app.infrastructure.repository import SqlSongRepository
from app.infrastructure.slots import StubAnalysisSlot
from app.application.analyze_song import AnalyzeSong

def get_repo(session: Session = Depends(get_session)) -> SqlSongRepository:
    return SqlSongRepository(session)

def get_analyze_song(session: Session = Depends(get_session)) -> AnalyzeSong:
    # A0 wires the stub slot here; swap StubAnalysisSlot for real slots in A1 without touching routes.
    return AnalyzeSong(SqlSongRepository(session), StubAnalysisSlot())
```

```python
# server/app/api/routes.py
from fastapi import APIRouter, Depends, HTTPException
from app.api.schemas import SubmitRequest
from app.api.deps import get_repo, get_analyze_song
from app.application.analyze_song import AnalyzeSong
from app.infrastructure.repository import SqlSongRepository
from app.infrastructure import youtube

router = APIRouter()

@router.get("/health")
def health():
    return {"status": "ok"}

@router.post("/songs")
def submit_song(body: SubmitRequest, uc: AnalyzeSong = Depends(get_analyze_song)):
    vid = youtube.parse_video_id(body.url)
    title, duration = youtube.fetch_meta(vid)
    return uc.execute(vid, title, duration).to_dict()

@router.get("/songs/{youtube_id}")
def get_song(youtube_id: str, repo: SqlSongRepository = Depends(get_repo)):
    result = repo.get(youtube_id)
    if not result:
        raise HTTPException(404, "not analyzed yet")
    return result.to_dict()

@router.get("/songs")
def recent(repo: SqlSongRepository = Depends(get_repo)):
    return [{"youtubeId": yid, "title": t} for yid, t in repo.recent()]
```

```python
# server/app/main.py  (replace Task 1 body)
from fastapi import FastAPI
from app.infrastructure.db import init_db
from app.api.routes import router

app = FastAPI(title="ChordMind")

@app.on_event("startup")
def _startup():
    init_db()

app.include_router(router)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && .venv/bin/python -m pytest tests/ -v`
Expected: PASS (all tests, including Task 1's `test_health.py`)

- [ ] **Step 5: Commit**

```bash
git add server/ && git commit -m "feat(server): API layer (DTO, DI, routes) wired to use case"
```

---

### Task 7: Flutter scaffold + theme (design system)

**Files:**
- Create: `app/pubspec.yaml`
- Create: `app/lib/core/theme.dart`
- Create: `app/lib/main.dart`
- Test: `app/test/theme_test.dart`

**Interfaces:**
- Produces: `chordMindLight` and `chordMindDark` `ThemeData`; a `ChordMindColors` extension with semantic tokens `chordActive`, `beatMarker`, `surfaceAlt`. `main.dart` runs `MaterialApp` with `themeMode: system`.

- [ ] **Step 1: Create the Flutter project shell**

Run: `cd app && flutter create . --platforms=android,ios,web --org com.chordmind`
Then add to `pubspec.yaml` dependencies: `flutter_riverpod: ^2.5.0`, `dio: ^5.4.0`, `youtube_player_iframe: ^5.1.0`, `go_router: ^14.0.0`.

- [ ] **Step 2: Write the failing test**

```dart
// app/test/theme_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';

void main() {
  test('themes expose ChordMind semantic colors', () {
    final c = chordMindLight.extension<ChordMindColors>();
    expect(c, isNotNull);
    expect(chordMindDark.extension<ChordMindColors>(), isNotNull);
    expect(c!.chordActive, isNot(c.beatMarker));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd app && flutter test test/theme_test.dart`
Expected: FAIL (theme.dart not found)

- [ ] **Step 4: Write the theme + main**

```dart
// app/lib/core/theme.dart
import 'package:flutter/material.dart';

@immutable
class ChordMindColors extends ThemeExtension<ChordMindColors> {
  final Color chordActive;
  final Color beatMarker;
  final Color surfaceAlt;
  const ChordMindColors({
    required this.chordActive,
    required this.beatMarker,
    required this.surfaceAlt,
  });
  @override
  ChordMindColors copyWith({Color? chordActive, Color? beatMarker, Color? surfaceAlt}) =>
      ChordMindColors(
        chordActive: chordActive ?? this.chordActive,
        beatMarker: beatMarker ?? this.beatMarker,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      );
  @override
  ChordMindColors lerp(ChordMindColors? o, double t) => o ?? this;
}

// Fresh ChordMind identity: deep indigo + warm amber accent.
const _seed = Color(0xFF4F46E5);

ThemeData _build(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [
      ChordMindColors(
        chordActive: const Color(0xFFF59E0B),
        beatMarker: scheme.primary,
        surfaceAlt: scheme.surfaceContainerHighest,
      ),
    ],
  );
}

final chordMindLight = _build(Brightness.light);
final chordMindDark = _build(Brightness.dark);
```

```dart
// app/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';

void main() => runApp(const ProviderScope(child: ChordMindApp()));

class ChordMindApp extends StatelessWidget {
  const ChordMindApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ChordMind',
        theme: chordMindLight,
        darkTheme: chordMindDark,
        themeMode: ThemeMode.system,
        home: const Scaffold(body: Center(child: Text('ChordMind'))),
      );
}
```

- [ ] **Step 5: Run test + web build to verify**

Run: `cd app && flutter test test/theme_test.dart && flutter build web`
Expected: test PASS; web build succeeds.

- [ ] **Step 6: Commit**

```bash
git add app && git commit -m "feat(app): flutter scaffold + ChordMind theme"
```

---

### Task 8: Dart AnalysisResult models

**Files:**
- Create: `app/lib/core/models.dart`
- Test: `app/test/models_test.dart`

**Interfaces:**
- Produces: classes `AnalysisResult`, `Source`, `Beat`, `Chord`, `SyncChord`, `Segment`, each with `fromJson(Map)`. Field names **exactly** mirror Task 2's wire contract (`songId`, `synchronizedChords`, `beatIndex`, `timeSignature`, …).
- Consumes: JSON identical to `POST /songs` response (Task 6).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/models.dart';

void main() {
  test('parses AnalysisResult from server JSON', () {
    final json = {
      'songId': 'abc',
      'source': {'youtubeId': 'abc', 'title': 'T', 'duration': 100.0, 'bpm': 120.0, 'timeSignature': 4},
      'key': 'C major',
      'beats': [{'time': 0.5, 'beatNum': 1}],
      'downbeats': [0.5],
      'chords': [{'chord': 'C', 'start': 0.5, 'end': 2.0, 'confidence': 0.9}],
      'synchronizedChords': [{'chord': 'C', 'beatIndex': 0}],
      'segments': [{'label': 'verse', 'start': 0.0, 'end': 100.0}],
      'melody': null,
    };
    final r = AnalysisResult.fromJson(json);
    expect(r.source.youtubeId, 'abc');
    expect(r.synchronizedChords.first.chord, 'C');
    expect(r.beats.length, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models_test.dart`
Expected: FAIL (models.dart not found)

- [ ] **Step 3: Write the models**

```dart
// app/lib/core/models.dart
class Source {
  final String youtubeId, title;
  final double duration, bpm;
  final int timeSignature;
  Source.fromJson(Map j)
      : youtubeId = j['youtubeId'],
        title = j['title'],
        duration = (j['duration'] as num).toDouble(),
        bpm = (j['bpm'] as num).toDouble(),
        timeSignature = j['timeSignature'];
}

class Beat {
  final double time;
  final int beatNum;
  Beat.fromJson(Map j) : time = (j['time'] as num).toDouble(), beatNum = j['beatNum'];
}

class Chord {
  final String chord;
  final double start, end, confidence;
  Chord.fromJson(Map j)
      : chord = j['chord'],
        start = (j['start'] as num).toDouble(),
        end = (j['end'] as num).toDouble(),
        confidence = (j['confidence'] as num).toDouble();
}

class SyncChord {
  final String chord;
  final int beatIndex;
  SyncChord.fromJson(Map j) : chord = j['chord'], beatIndex = j['beatIndex'];
}

class Segment {
  final String label;
  final double start, end;
  Segment.fromJson(Map j)
      : label = j['label'], start = (j['start'] as num).toDouble(), end = (j['end'] as num).toDouble();
}

class AnalysisResult {
  final String songId, key;
  final Source source;
  final List<Beat> beats;
  final List<double> downbeats;
  final List<Chord> chords;
  final List<SyncChord> synchronizedChords;
  final List<Segment> segments;
  AnalysisResult.fromJson(Map j)
      : songId = j['songId'],
        key = j['key'],
        source = Source.fromJson(j['source']),
        beats = [for (final b in j['beats']) Beat.fromJson(b)],
        downbeats = [for (final d in j['downbeats']) (d as num).toDouble()],
        chords = [for (final c in j['chords']) Chord.fromJson(c)],
        synchronizedChords = [for (final s in j['synchronizedChords']) SyncChord.fromJson(s)],
        segments = [for (final s in j['segments']) Segment.fromJson(s)];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/models_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app && git commit -m "feat(app): AnalysisResult dart models"
```

---

### Task 9: API client + repository (data layer)

**Files:**
- Create: `app/lib/core/api.dart`
- Create: `app/lib/core/song_repository.dart`
- Test: `app/test/api_test.dart`

**Interfaces:**
- Produces: `ChordMindApi(Dio dio, {String baseUrl})` with `Future<AnalysisResult> submit(String url)` (POST /songs), `Future<AnalysisResult> get(String youtubeId)` (GET /songs/{id}), `Future<List<({String youtubeId, String title})>> recent()`. A Riverpod `apiProvider`.
- Produces (clean-arch boundary the UI depends on): abstract `SongRepository` with the same three methods; `ApiSongRepository(ChordMindApi)` implements it; Riverpod `songRepositoryProvider`. **UI/features depend on `songRepositoryProvider`, never on `ChordMindApi`/Dio directly.**
- Consumes: `AnalysisResult.fromJson` (Task 8).

- [ ] **Step 1: Write the failing test** (Dio with a mock adapter)

```dart
// app/test/api_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/api.dart';

class _FakeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(opts, stream, future) async => ResponseBody.fromString(
      '{"songId":"abc","source":{"youtubeId":"abc","title":"T","duration":100.0,"bpm":120.0,"timeSignature":4},"key":"C major","beats":[],"downbeats":[],"chords":[],"synchronizedChords":[],"segments":[]}',
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  @override
  void close({bool force = false}) {}
}

void main() {
  test('submit parses AnalysisResult', () async {
    final dio = Dio()..httpClientAdapter = _FakeAdapter();
    final api = ChordMindApi(dio, baseUrl: 'http://x');
    final r = await api.submit('https://youtu.be/abc');
    expect(r.songId, 'abc');
    expect(r.key, 'C major');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/api_test.dart`
Expected: FAIL (api.dart not found)

- [ ] **Step 3: Write the client**

```dart
// app/lib/core/api.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';

class ChordMindApi {
  final Dio _dio;
  final String baseUrl;
  ChordMindApi(this._dio, {this.baseUrl = 'http://localhost:8000'});

  Future<AnalysisResult> submit(String url) async {
    final r = await _dio.post('$baseUrl/songs', data: {'url': url});
    return AnalysisResult.fromJson(r.data as Map);
  }

  Future<AnalysisResult> get(String youtubeId) async {
    final r = await _dio.get('$baseUrl/songs/$youtubeId');
    return AnalysisResult.fromJson(r.data as Map);
  }

  Future<List<({String youtubeId, String title})>> recent() async {
    final r = await _dio.get('$baseUrl/songs');
    return [for (final s in r.data as List) (youtubeId: s['youtubeId'] as String, title: s['title'] as String)];
  }
}

final apiProvider = Provider((_) => ChordMindApi(Dio()));
```

```dart
// app/lib/core/song_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api.dart';
import 'models.dart';

/// Clean-arch boundary: features depend on this, not on ChordMindApi/Dio.
abstract class SongRepository {
  Future<AnalysisResult> submit(String url);
  Future<AnalysisResult> get(String youtubeId);
  Future<List<({String youtubeId, String title})>> recent();
}

class ApiSongRepository implements SongRepository {
  final ChordMindApi _api;
  ApiSongRepository(this._api);
  @override
  Future<AnalysisResult> submit(String url) => _api.submit(url);
  @override
  Future<AnalysisResult> get(String youtubeId) => _api.get(youtubeId);
  @override
  Future<List<({String youtubeId, String title})>> recent() => _api.recent();
}

final songRepositoryProvider =
    Provider<SongRepository>((ref) => ApiSongRepository(ref.read(apiProvider)));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/api_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app && git commit -m "feat(app): API client + SongRepository (data layer)"
```

---

### Task 10: Chord grid sync logic + widget

**Files:**
- Create: `app/lib/features/chord_grid/grid_sync.dart`
- Create: `app/lib/features/chord_grid/chord_grid.dart`
- Test: `app/test/grid_sync_test.dart`

**Interfaces:**
- Produces: `int activeChordIndex(AnalysisResult r, double positionSeconds)` — returns the index into `synchronizedChords` whose chord is sounding at `positionSeconds` (via the `chords[]` start/end ranges), or -1 before the first chord. `ChordGrid` widget takes `AnalysisResult` + `positionSeconds` and highlights the active cell using `ChordMindColors.chordActive`.
- Consumes: `AnalysisResult` (Task 8), theme (Task 7).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/grid_sync_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/features/chord_grid/grid_sync.dart';

AnalysisResult _r() => AnalysisResult.fromJson({
      'songId': 'a', 'key': 'C major',
      'source': {'youtubeId': 'a', 'title': 'T', 'duration': 4.0, 'bpm': 120.0, 'timeSignature': 4},
      'beats': [], 'downbeats': [],
      'chords': [
        {'chord': 'C', 'start': 0.0, 'end': 2.0, 'confidence': 1.0},
        {'chord': 'G', 'start': 2.0, 'end': 4.0, 'confidence': 1.0},
      ],
      'synchronizedChords': [
        {'chord': 'C', 'beatIndex': 0},
        {'chord': 'G', 'beatIndex': 2},
      ],
      'segments': [],
    });

void main() {
  test('activeChordIndex maps position to chord cell', () {
    final r = _r();
    expect(activeChordIndex(r, 0.5), 0);
    expect(activeChordIndex(r, 2.5), 1);
    expect(activeChordIndex(r, -1.0), -1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/grid_sync_test.dart`
Expected: FAIL (grid_sync.dart not found)

- [ ] **Step 3: Write sync logic + grid widget**

```dart
// app/lib/features/chord_grid/grid_sync.dart
import 'package:chordmind/core/models.dart';

int activeChordIndex(AnalysisResult r, double pos) {
  for (var i = 0; i < r.chords.length; i++) {
    if (pos >= r.chords[i].start && pos < r.chords[i].end) return i;
  }
  return -1;
}
```

```dart
// app/lib/features/chord_grid/chord_grid.dart
import 'package:flutter/material.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/theme.dart';
import 'grid_sync.dart';

class ChordGrid extends StatelessWidget {
  final AnalysisResult result;
  final double positionSeconds;
  final void Function(String chord)? onTapChord;
  const ChordGrid({super.key, required this.result, required this.positionSeconds, this.onTapChord});

  @override
  Widget build(BuildContext context) {
    final active = activeChordIndex(result, positionSeconds);
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, childAspectRatio: 1.4, mainAxisSpacing: 6, crossAxisSpacing: 6),
      itemCount: result.synchronizedChords.length,
      itemBuilder: (ctx, i) {
        final c = result.synchronizedChords[i];
        final on = i == active;
        return InkWell(
          onTap: () => onTapChord?.call(c.chord),
          child: Container(
            decoration: BoxDecoration(
              color: on ? cm.chordActive : cm.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(c.chord,
                style: TextStyle(fontSize: 18, fontWeight: on ? FontWeight.bold : FontWeight.normal)),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/grid_sync_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app && git commit -m "feat(app): chord grid + sync logic"
```

---

### Task 11: Chord diagrams (guitar + piano)

**Files:**
- Create: `app/lib/features/diagrams/voicings.dart`
- Create: `app/lib/features/diagrams/guitar_diagram.dart`
- Create: `app/lib/features/diagrams/piano_diagram.dart`
- Create: `app/lib/features/diagrams/chord_diagram_sheet.dart`
- Test: `app/test/voicings_test.dart`

**Interfaces:**
- Produces:
  - `GuitarVoicing({List<int> frets, int baseFret, List<int> barres})` and `const guitarVoicings` map for common open chords (C, G, Am, F, D, E, Em, Dm). `frets` is 6 entries low→high E, `-1` = muted, `0` = open. Mirrors `reference/.../guitarVoicing.ts` shape.
  - `pianoNotes(String chord) -> List<int>` returning semitone offsets (0–11) for the chord's notes (root/third/fifth) for major & minor triads.
  - `GuitarDiagram(GuitarVoicing v)` widget; `PianoDiagram(List<int> notes)` widget; `showChordDiagram(BuildContext, String chord)` opens a bottom sheet with both (guitar shown only if a voicing exists).
- Consumes: theme (Task 7).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/voicings_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/features/diagrams/voicings.dart';

void main() {
  test('common chords have 6-string voicings', () {
    expect(guitarVoicings['C']!.frets.length, 6);
    expect(guitarVoicings['G']!.frets.length, 6);
  });
  test('pianoNotes returns triad for major and minor', () {
    expect(pianoNotes('C'), [0, 4, 7]);   // C E G
    expect(pianoNotes('Am'), [9, 0, 4]);  // A C E
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/voicings_test.dart`
Expected: FAIL (voicings.dart not found)

- [ ] **Step 3: Write voicings + diagram widgets**

```dart
// app/lib/features/diagrams/voicings.dart
class GuitarVoicing {
  final List<int> frets; // 6 strings low->high, -1 muted, 0 open
  final int baseFret;
  final List<int> barres;
  const GuitarVoicing(this.frets, {this.baseFret = 1, this.barres = const []});
}

// ponytail: small static table of open chords; expand or compute from a library if needed.
const guitarVoicings = <String, GuitarVoicing>{
  'C':  GuitarVoicing([-1, 3, 2, 0, 1, 0]),
  'G':  GuitarVoicing([3, 2, 0, 0, 0, 3]),
  'Am': GuitarVoicing([-1, 0, 2, 2, 1, 0]),
  'F':  GuitarVoicing([1, 3, 3, 2, 1, 1], barres: [1]),
  'D':  GuitarVoicing([-1, -1, 0, 2, 3, 2]),
  'E':  GuitarVoicing([0, 2, 2, 1, 0, 0]),
  'Em': GuitarVoicing([0, 2, 2, 0, 0, 0]),
  'Dm': GuitarVoicing([-1, -1, 0, 2, 3, 1]),
};

const _roots = {'C':0,'C#':1,'Db':1,'D':2,'D#':3,'Eb':3,'E':4,'F':5,
  'F#':6,'Gb':6,'G':7,'G#':8,'Ab':8,'A':9,'A#':10,'Bb':10,'B':11};

List<int> pianoNotes(String chord) {
  final isMinor = chord.contains('m') && !chord.contains('maj');
  final rootName = chord.replaceAll(RegExp(r'(m|maj|7|dim|aug|sus).*$'), '');
  final root = _roots[rootName] ?? 0;
  final third = isMinor ? 3 : 4;
  return [root, (root + third) % 12, (root + 7) % 12];
}
```

```dart
// app/lib/features/diagrams/guitar_diagram.dart
import 'package:flutter/material.dart';
import 'voicings.dart';

class GuitarDiagram extends StatelessWidget {
  final GuitarVoicing v;
  const GuitarDiagram(this.v, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 160,
        child: CustomPaint(painter: _GuitarPainter(v, Theme.of(context).colorScheme.onSurface)),
      );
}

class _GuitarPainter extends CustomPainter {
  final GuitarVoicing v;
  final Color color;
  _GuitarPainter(this.v, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    const strings = 6, frets = 5;
    final dx = size.width / (strings - 1), dy = size.height / frets;
    final p = Paint()..color = color..strokeWidth = 1;
    for (var i = 0; i < strings; i++) {
      canvas.drawLine(Offset(i * dx, 0), Offset(i * dx, size.height), p);
    }
    for (var f = 0; f <= frets; f++) {
      canvas.drawLine(Offset(0, f * dy), Offset(size.width, f * dy), p);
    }
    final dot = Paint()..color = color..style = PaintingStyle.fill;
    for (var s = 0; s < strings; s++) {
      final fret = v.frets[s];
      if (fret > 0) {
        canvas.drawCircle(Offset(s * dx, (fret - 0.5) * dy), 7, dot);
      }
    }
  }
  @override
  bool shouldRepaint(_) => false;
}
```

```dart
// app/lib/features/diagrams/piano_diagram.dart
import 'package:flutter/material.dart';
import 'package:chordmind/core/theme.dart';

class PianoDiagram extends StatelessWidget {
  final List<int> notes; // semitone offsets 0..11
  const PianoDiagram(this.notes, {super.key});
  static const _whites = [0, 2, 4, 5, 7, 9, 11];
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return SizedBox(
      height: 90,
      child: Row(
        children: [
          for (final w in _whites)
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(1),
                color: notes.contains(w) ? cm.chordActive : Colors.white,
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}
```

```dart
// app/lib/features/diagrams/chord_diagram_sheet.dart
import 'package:flutter/material.dart';
import 'voicings.dart';
import 'guitar_diagram.dart';
import 'piano_diagram.dart';

void showChordDiagram(BuildContext context, String chord) {
  showModalBottomSheet(
    context: context,
    builder: (_) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(chord, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        if (guitarVoicings[chord] != null) GuitarDiagram(guitarVoicings[chord]!),
        const SizedBox(height: 12),
        PianoDiagram(pianoNotes(chord)),
      ]),
    ),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/voicings_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app && git commit -m "feat(app): guitar + piano chord diagrams"
```

---

### Task 12: Player screen + routing + placeholder tabs

**Files:**
- Create: `app/lib/features/player/player_screen.dart`
- Create: `app/lib/features/home/home_screen.dart`
- Create: `app/lib/core/router.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/home_test.dart`

**Interfaces:**
- Produces:
  - `HomeScreen`: a `TextField` for a YouTube URL + "Analyze" button → calls `api.submit(url)` then routes to `/player/{youtubeId}`. Recent list below.
  - `PlayerScreen(youtubeId)`: loads analysis via `api.get`, shows the YouTube iframe player on top, `ChordGrid` below (driven by player position), and a bottom `TabBar` with tabs **Chords / Lyrics / Re-harm / Band / Versions** where the last three are placeholder `Center(Text('Coming soon'))`. Tapping a chord cell calls `showChordDiagram`.
  - `router` (go_router) with `/` and `/player/:id`.
- Consumes: `songRepositoryProvider` (Task 9), `ChordGrid` (Task 10), `showChordDiagram` (Task 11).

- [ ] **Step 1: Write the failing test** (widget test for HomeScreen renders input + button)

```dart
// app/test/home_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/features/home/home_screen.dart';

void main() {
  testWidgets('home shows url field and analyze button', (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: HomeScreen())));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Analyze'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/home_test.dart`
Expected: FAIL (home_screen.dart not found)

- [ ] **Step 3: Write home, player, router, wire main**

```dart
// app/lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:chordmind/core/song_repository.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  Future<void> _analyze() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(songRepositoryProvider).submit(_ctrl.text);
      if (mounted) context.go('/player/${r.source.youtubeId}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ChordMind')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                  labelText: 'YouTube link', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _analyze, child: const Text('Analyze')),
          ]),
        ),
      );
}
```

```dart
// app/lib/features/player/player_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:chordmind/core/song_repository.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/features/chord_grid/chord_grid.dart';
import 'package:chordmind/features/diagrams/chord_diagram_sheet.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String youtubeId;
  const PlayerScreen(this.youtubeId, {super.key});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final YoutubePlayerController _yt;
  AnalysisResult? _r;
  double _pos = 0;

  @override
  void initState() {
    super.initState();
    _yt = YoutubePlayerController.fromVideoId(
        videoId: widget.youtubeId, params: const YoutubePlayerParams(showControls: true));
    _yt.videoStateStream.listen((s) {
      if (mounted) setState(() => _pos = s.position.inMilliseconds / 1000.0);
    });
    ref.read(songRepositoryProvider).get(widget.youtubeId).then((r) => mounted ? setState(() => _r = r) : null);
  }

  @override
  void dispose() {
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(r?.source.title ?? 'Loading…'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Chords'), Tab(text: 'Lyrics'), Tab(text: 'Re-harm'),
            Tab(text: 'Band'), Tab(text: 'Versions'),
          ]),
        ),
        body: Column(children: [
          YoutubePlayer(controller: _yt),
          Expanded(
            child: r == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [
                    ChordGrid(
                        result: r,
                        positionSeconds: _pos,
                        onTapChord: (c) => showChordDiagram(context, c)),
                    const Center(child: Text('Lyrics coming soon')),
                    const Center(child: Text('On-device re-harmonization coming soon')),
                    const Center(child: Text('Band sync coming soon')),
                    const Center(child: Text('Versions coming soon')),
                  ]),
          ),
        ]),
      ),
    );
  }
}
```

```dart
// app/lib/core/router.dart
import 'package:go_router/go_router.dart';
import 'package:chordmind/features/home/home_screen.dart';
import 'package:chordmind/features/player/player_screen.dart';

final router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
  GoRoute(path: '/player/:id', builder: (_, s) => PlayerScreen(s.pathParameters['id']!)),
]);
```

```dart
// app/lib/main.dart  (replace body)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/router.dart';

void main() => runApp(const ProviderScope(child: ChordMindApp()));

class ChordMindApp extends StatelessWidget {
  const ChordMindApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'ChordMind',
        theme: chordMindLight,
        darkTheme: chordMindDark,
        themeMode: ThemeMode.system,
        routerConfig: router,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/home_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app && git commit -m "feat(app): home + player screens, routing, placeholder tabs"
```

---

### Task 13: End-to-end verification (web)

**Files:**
- Create: `docs/superpowers/plans/A0-VERIFY.md` (manual run notes)

**Interfaces:**
- Consumes: everything above. No new code — this task proves the vertical works.

- [ ] **Step 1: Start the server**

Run: `cd server && docker compose up -d db && uvicorn app.main:app --reload`
Expected: server on `http://localhost:8000`, `GET /health` → `{"status":"ok"}`.

- [ ] **Step 2: Smoke-test the API**

Run: `curl -s -X POST localhost:8000/songs -H 'content-type: application/json' -d '{"url":"https://youtu.be/dQw4w9WgXcQ"}' | head -c 200`
Expected: JSON beginning with `{"songId":"dQw4w9WgXcQ"...` and a `synchronizedChords` array.

- [ ] **Step 3: Run the full test suites**

Run: `cd server && python -m pytest -q && cd ../app && flutter test`
Expected: all tests PASS.

- [ ] **Step 4: Run the app on web and click through**

Run: `cd app && flutter run -d chrome` (point api baseUrl at `http://localhost:8000`)
Expected: paste a YouTube URL → Analyze → player screen with chord grid; tapping a chord cell opens the guitar+piano diagram sheet; toggling OS dark mode flips the theme.

- [ ] **Step 5: Record results + commit**

Write a short results note in `A0-VERIFY.md` (what passed, any deviations) and commit:
```bash
git add docs/superpowers/plans/A0-VERIFY.md && git commit -m "docs: A0 verification notes"
```

---

## Self-Review

**Spec coverage:** Section 1 phases → this plan is A0 (A1–A3 deferred, noted in header). Section 2 contract → domain entity (T2) + dart models (T8), names matched. Section 3 app modules → home (T12), player (T12), chord_grid (T10), diagrams (T11), placeholder reharm/band/versions tabs (T12), theme (T7). Section 4 server modules → api adapters (T6), application use case = "ml_worker" role (T5), ml_interface ports + stub slot (T2 ports / T4 impl), db Postgres repository (T1/T3); signaling deferred to A2 per spec. Section 5 theme → T7. Section 6 placeholders → T12 tabs + T4 stub slot. Section 7 done criteria → T13.

**Clean architecture:** domain (T2) imports no framework; application use case (T5) depends only on ports and is tested with a fake repo; infrastructure (T3/T4) implements ports; api (T6) wires via DI. Client mirrors with `SongRepository` boundary (T9) consumed by features (T12).

**Placeholder scan:** Deferred items (signaling, versioning, real models) are explicitly out of A0 scope per spec, not plan gaps. No TBD/TODO in code steps.

**Type consistency:** `AnalysisResult` field names identical across T2/T8 (`songId`, `synchronizedChords`, `beatIndex`, `timeSignature`); domain `to_dict()` (T2) ↔ Dart `fromJson` (T8) ↔ API output (T6). `ModelSlot.run(youtube_id,title,duration)` consistent T2/T4/T5. `SongRepository.get/save/recent` consistent T2/T3/T5. `AnalyzeSong.execute` T5↔T6. `activeChordIndex` T10. `showChordDiagram`, `guitarVoicings`, `pianoNotes` T11↔T12. `songRepositoryProvider`/`SongRepository.submit/get/recent` T9↔T12.
