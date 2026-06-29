# ChordMind App A0 — Core Vertical Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A running, demoable ChordMind vertical: paste a YouTube link → server returns a (stubbed) `AnalysisResult` → Flutter app shows a synced chord grid, guitar/piano diagrams, lyrics, and a fresh light/dark theme.

**Architecture:** FastAPI + Postgres server with an `ml_interface` ModelSlot contract whose slots are **stubs returning fixtures**; an `ml_worker` runs slots on submit and caches the result. Flutter app (mobile-first, web as the dev/test surface) consumes the frozen `AnalysisResult` JSON contract via a REST client.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2.x, Pydantic v2, Postgres 16 (Docker), pytest. Flutter 3.x (Dart 3), Riverpod, dio, youtube_player_iframe, flutter_test.

## Global Constraints

- Audio input source: **YouTube link only** for A0.
- `AnalysisResult` JSON shape is **frozen** (Task 2 / Task 9) — server and app must match field-for-field. No app code reads model internals.
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

### Task 2: AnalysisResult contract (Pydantic)

**Files:**
- Create: `server/app/schemas.py`
- Test: `server/tests/test_schemas.py`

**Interfaces:**
- Produces: Pydantic models `Source`, `Beat`, `Chord`, `SyncChord`, `Segment`, `AnalysisResult`. Field names exactly: `AnalysisResult(songId, source, key, beats, downbeats, chords, synchronizedChords, segments, melody)`. These names are the frozen wire contract Task 9 (Dart) must mirror.

- [ ] **Step 1: Write the failing test**

```python
# server/tests/test_schemas.py
from app.schemas import AnalysisResult

def test_analysis_result_roundtrip():
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
    r = AnalysisResult.model_validate(data)
    assert r.synchronizedChords[0].chord == "C"
    assert r.model_dump(by_alias=True)["songId"] == "s1"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && python -m pytest tests/test_schemas.py -v`
Expected: FAIL (cannot import AnalysisResult)

- [ ] **Step 3: Write the schemas**

```python
# server/app/schemas.py
from pydantic import BaseModel, ConfigDict

class _Base(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

class Source(_Base):
    youtubeId: str
    title: str
    duration: float
    bpm: float
    timeSignature: int

class Beat(_Base):
    time: float
    beatNum: int

class Chord(_Base):
    chord: str
    start: float
    end: float
    confidence: float

class SyncChord(_Base):
    chord: str
    beatIndex: int

class Segment(_Base):
    label: str
    start: float
    end: float

class AnalysisResult(_Base):
    songId: str
    source: Source
    key: str
    beats: list[Beat] = []
    downbeats: list[float] = []
    chords: list[Chord] = []
    synchronizedChords: list[SyncChord] = []
    segments: list[Segment] = []
    melody: dict | None = None
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && python -m pytest tests/test_schemas.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/ && git commit -m "feat(server): freeze AnalysisResult contract"
```

---

### Task 3: DB models + session

**Files:**
- Create: `server/app/db.py`
- Create: `server/app/models.py`
- Test: `server/tests/test_models.py`

**Interfaces:**
- Produces: `Base`, `get_session()` (yields a SQLAlchemy `Session`), `init_db()` (creates tables). ORM models `Song(id, youtube_id, title, analysis_json, created_at)`. (Tables `versions`/`votes`/`users` are deferred to A3 — do NOT create them here.)
- Consumes: `get_settings().database_url` (Task 1).

- [ ] **Step 1: Write the failing test** (uses an in-memory SQLite override for speed)

```python
# server/tests/test_models.py
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.db import Base
from app.models import Song

def test_song_persist():
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    Session = sessionmaker(engine)
    with Session() as s:
        s.add(Song(id="s1", youtube_id="abc", title="T", analysis_json={"k": 1}))
        s.commit()
        got = s.get(Song, "s1")
        assert got.youtube_id == "abc"
        assert got.analysis_json == {"k": 1}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && python -m pytest tests/test_models.py -v`
Expected: FAIL (cannot import app.db)

- [ ] **Step 3: Write db + models**

```python
# server/app/db.py
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from app.config import get_settings

Base = declarative_base()
_engine = create_engine(get_settings().database_url, future=True)
SessionLocal = sessionmaker(bind=_engine, future=True)

def init_db():
    Base.metadata.create_all(_engine)

def get_session():
    with SessionLocal() as s:
        yield s
```

```python
# server/app/models.py
from datetime import datetime
from sqlalchemy import String, DateTime, JSON
from sqlalchemy.orm import Mapped, mapped_column
from app.db import Base

class Song(Base):
    __tablename__ = "songs"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    youtube_id: Mapped[str] = mapped_column(String, index=True)
    title: Mapped[str] = mapped_column(String)
    analysis_json: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && python -m pytest tests/test_models.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/ && git commit -m "feat(server): Song ORM model + db session"
```

---

### Task 4: ml_interface ModelSlot + StubSlot fixtures

**Files:**
- Create: `server/app/ml_interface/__init__.py`
- Create: `server/app/ml_interface/slots.py`
- Create: `server/app/ml_interface/fixtures.py`
- Test: `server/tests/test_slots.py`

**Interfaces:**
- Produces: `ModelSlot` ABC with `def run(self, ctx: dict) -> dict`. `StubAnalysisSlot.run(ctx)` returns a dict that validates as `AnalysisResult` (Task 2), filling beats/chords/synchronizedChords/segments from a hand-authored fixture. `ctx` carries `{"youtubeId", "title", "duration"}`.

- [ ] **Step 1: Write the failing test**

```python
# server/tests/test_slots.py
from app.ml_interface.slots import StubAnalysisSlot
from app.schemas import AnalysisResult

def test_stub_slot_returns_valid_analysis():
    out = StubAnalysisSlot().run({"youtubeId": "abc", "title": "Demo", "duration": 120.0})
    r = AnalysisResult.model_validate(out)
    assert r.source.youtubeId == "abc"
    assert len(r.synchronizedChords) > 0
    # beatIndex must reference a real beat
    assert max(c.beatIndex for c in r.synchronizedChords) < len(r.beats)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && python -m pytest tests/test_slots.py -v`
Expected: FAIL (cannot import)

- [ ] **Step 3: Write slots + fixtures**

```python
# server/app/ml_interface/__init__.py
```

```python
# server/app/ml_interface/fixtures.py
# A simple 8-beat I–V–vi–IV loop in C, 2 beats per chord, 120 bpm.
PROGRESSION = ["C", "G", "Am", "F"]

def build_fixture(youtube_id: str, title: str, duration: float) -> dict:
    bpm, beats_per_chord = 120.0, 2
    spb = 60.0 / bpm  # seconds per beat
    n_beats = max(8, int(duration / spb))
    beats = [{"time": round(i * spb, 3), "beatNum": (i % 4) + 1} for i in range(n_beats)]
    downbeats = [b["time"] for b in beats if b["beatNum"] == 1]
    chords, sync = [], []
    for i in range(0, n_beats, beats_per_chord):
        name = PROGRESSION[(i // beats_per_chord) % len(PROGRESSION)]
        start = beats[i]["time"]
        end = beats[min(i + beats_per_chord, n_beats - 1)]["time"]
        chords.append({"chord": name, "start": start, "end": end, "confidence": 0.95})
        sync.append({"chord": name, "beatIndex": i})
    return {
        "songId": youtube_id,
        "source": {"youtubeId": youtube_id, "title": title,
                   "duration": duration, "bpm": bpm, "timeSignature": 4},
        "key": "C major",
        "beats": beats, "downbeats": downbeats,
        "chords": chords, "synchronizedChords": sync,
        "segments": [{"label": "verse", "start": 0.0, "end": duration}],
        "melody": None,
    }
```

```python
# server/app/ml_interface/slots.py
from abc import ABC, abstractmethod
from app.ml_interface.fixtures import build_fixture

class ModelSlot(ABC):
    @abstractmethod
    def run(self, ctx: dict) -> dict: ...

class StubAnalysisSlot(ModelSlot):
    """A0 placeholder. Replace with real beat/chord/key/segment slots in A1."""
    def run(self, ctx: dict) -> dict:
        return build_fixture(ctx["youtubeId"], ctx["title"], ctx["duration"])
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && python -m pytest tests/test_slots.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/ && git commit -m "feat(server): ml_interface ModelSlot + stub fixture slot"
```

---

### Task 5: ml_worker — analyze + cache

**Files:**
- Create: `server/app/ml_worker.py`
- Test: `server/tests/test_worker.py`

**Interfaces:**
- Produces: `analyze_song(session, youtube_id, title, duration) -> dict`. Returns cached `analysis_json` if a `Song` with that `youtube_id` exists; otherwise runs `StubAnalysisSlot`, persists a `Song`, returns the dict. Song `id` = `youtube_id` for A0.
- Consumes: `StubAnalysisSlot` (Task 4), `Song` (Task 3).

- [ ] **Step 1: Write the failing test**

```python
# server/tests/test_worker.py
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.db import Base
from app.models import Song
from app.ml_worker import analyze_song

def _session():
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    return sessionmaker(engine)()

def test_analyze_creates_then_caches():
    s = _session()
    first = analyze_song(s, "abc", "Demo", 120.0)
    assert first["source"]["youtubeId"] == "abc"
    assert s.query(Song).count() == 1
    # second call must hit cache, not create a duplicate
    second = analyze_song(s, "abc", "Demo", 120.0)
    assert second == first
    assert s.query(Song).count() == 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && python -m pytest tests/test_worker.py -v`
Expected: FAIL (cannot import analyze_song)

- [ ] **Step 3: Write the worker**

```python
# server/app/ml_worker.py
from sqlalchemy.orm import Session
from app.models import Song
from app.ml_interface.slots import StubAnalysisSlot

# ponytail: in-process synchronous worker; swap to a job queue if pipeline gets slow.
def analyze_song(session: Session, youtube_id: str, title: str, duration: float) -> dict:
    existing = session.get(Song, youtube_id)
    if existing:
        return existing.analysis_json
    analysis = StubAnalysisSlot().run(
        {"youtubeId": youtube_id, "title": title, "duration": duration}
    )
    session.add(Song(id=youtube_id, youtube_id=youtube_id, title=title, analysis_json=analysis))
    session.commit()
    return analysis
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && python -m pytest tests/test_worker.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/ && git commit -m "feat(server): ml_worker analyze+cache"
```

---

### Task 6: API endpoints (submit + fetch)

**Files:**
- Modify: `server/app/main.py`
- Create: `server/app/youtube.py`
- Test: `server/tests/test_api.py`

**Interfaces:**
- Produces:
  - `POST /songs` body `{"url": "<youtube url>"}` → `AnalysisResult` JSON (runs worker, caches).
  - `GET /songs/{youtube_id}` → cached `AnalysisResult` or 404.
  - `GET /songs` → `[{youtubeId, title}]` recent list.
  - `youtube.py`: `parse_video_id(url) -> str`, `fetch_meta(video_id) -> tuple[str, float]` (title, duration). For A0 `fetch_meta` may return stub metadata if yt-dlp unavailable.
- Consumes: `analyze_song` (Task 5), `get_session` (Task 3), `init_db` (Task 3).

- [ ] **Step 1: Write the failing test** (override DB dependency with SQLite)

```python
# server/tests/test_api.py
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.db import Base, get_session
from app import youtube

def _client(monkeypatch):
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    Session = sessionmaker(engine)
    app.dependency_overrides[get_session] = lambda: (yield from [Session()])
    monkeypatch.setattr(youtube, "fetch_meta", lambda vid: ("Demo Song", 120.0))
    return TestClient(app)

def test_parse_video_id():
    assert youtube.parse_video_id("https://www.youtube.com/watch?v=abc123") == "abc123"
    assert youtube.parse_video_id("https://youtu.be/abc123") == "abc123"

def test_submit_and_fetch(monkeypatch):
    c = _client(monkeypatch)
    r = c.post("/songs", json={"url": "https://youtu.be/abc123"})
    assert r.status_code == 200
    assert r.json()["source"]["youtubeId"] == "abc123"
    g = c.get("/songs/abc123")
    assert g.status_code == 200
    assert g.json()["key"] == "C major"
    assert c.get("/songs/missing").status_code == 404
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && python -m pytest tests/test_api.py -v`
Expected: FAIL (cannot import youtube / routes missing)

- [ ] **Step 3: Write youtube helper + routes**

```python
# server/app/youtube.py
import re

_PATTERNS = [r"v=([\w-]{11})", r"youtu\.be/([\w-]{11})", r"([\w-]{11})$"]

def parse_video_id(url: str) -> str:
    for p in _PATTERNS:
        m = re.search(p, url)
        if m:
            return m.group(1)
    raise ValueError(f"cannot parse video id from {url!r}")

def fetch_meta(video_id: str) -> tuple[str, float]:
    # ponytail: real metadata via yt-dlp; falls back to stub if it fails (A0 uses stub analysis anyway).
    try:
        import yt_dlp
        with yt_dlp.YoutubeDL({"quiet": True, "skip_download": True}) as ydl:
            info = ydl.extract_info(f"https://youtu.be/{video_id}", download=False)
            return info.get("title", video_id), float(info.get("duration", 120.0))
    except Exception:
        return video_id, 120.0
```

```python
# server/app/main.py
from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from app.db import get_session, init_db
from app.models import Song
from app.ml_worker import analyze_song
from app import youtube

app = FastAPI(title="ChordMind")

@app.on_event("startup")
def _startup():
    init_db()

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/songs")
def submit_song(body: dict, session: Session = Depends(get_session)):
    vid = youtube.parse_video_id(body["url"])
    title, duration = youtube.fetch_meta(vid)
    return analyze_song(session, vid, title, duration)

@app.get("/songs/{youtube_id}")
def get_song(youtube_id: str, session: Session = Depends(get_session)):
    song = session.get(Song, youtube_id)
    if not song:
        raise HTTPException(404, "not analyzed yet")
    return song.analysis_json

@app.get("/songs")
def recent(session: Session = Depends(get_session)):
    rows = session.query(Song).order_by(Song.created_at.desc()).limit(20).all()
    return [{"youtubeId": s.youtube_id, "title": s.title} for s in rows]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && python -m pytest tests/test_api.py -v`
Expected: PASS (all 3 tests)

- [ ] **Step 5: Commit**

```bash
git add server/ && git commit -m "feat(server): songs submit/fetch/recent endpoints"
```

---

### Task 7: Flutter scaffold + theme (design system)

**Files:**
- Create: `app/mobile/pubspec.yaml`
- Create: `app/mobile/lib/core/theme.dart`
- Create: `app/mobile/lib/main.dart`
- Test: `app/mobile/test/theme_test.dart`

**Interfaces:**
- Produces: `chordMindLight` and `chordMindDark` `ThemeData`; a `ChordMindColors` extension with semantic tokens `chordActive`, `beatMarker`, `surfaceAlt`. `main.dart` runs `MaterialApp` with `themeMode: system`.

- [ ] **Step 1: Create the Flutter project shell**

Run: `cd app/mobile && flutter create . --platforms=android,ios,web --org com.chordmind`
Then add to `pubspec.yaml` dependencies: `flutter_riverpod: ^2.5.0`, `dio: ^5.4.0`, `youtube_player_iframe: ^5.1.0`, `go_router: ^14.0.0`.

- [ ] **Step 2: Write the failing test**

```dart
// app/mobile/test/theme_test.dart
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

Run: `cd app/mobile && flutter test test/theme_test.dart`
Expected: FAIL (theme.dart not found)

- [ ] **Step 4: Write the theme + main**

```dart
// app/mobile/lib/core/theme.dart
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
// app/mobile/lib/main.dart
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

Run: `cd app/mobile && flutter test test/theme_test.dart && flutter build web`
Expected: test PASS; web build succeeds.

- [ ] **Step 6: Commit**

```bash
git add app/mobile && git commit -m "feat(app): flutter scaffold + ChordMind theme"
```

---

### Task 8: Dart AnalysisResult models

**Files:**
- Create: `app/mobile/lib/core/models.dart`
- Test: `app/mobile/test/models_test.dart`

**Interfaces:**
- Produces: classes `AnalysisResult`, `Source`, `Beat`, `Chord`, `SyncChord`, `Segment`, each with `fromJson(Map)`. Field names **exactly** mirror Task 2's wire contract (`songId`, `synchronizedChords`, `beatIndex`, `timeSignature`, …).
- Consumes: JSON identical to `POST /songs` response (Task 6).

- [ ] **Step 1: Write the failing test**

```dart
// app/mobile/test/models_test.dart
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

Run: `cd app/mobile && flutter test test/models_test.dart`
Expected: FAIL (models.dart not found)

- [ ] **Step 3: Write the models**

```dart
// app/mobile/lib/core/models.dart
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

Run: `cd app/mobile && flutter test test/models_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/mobile && git commit -m "feat(app): AnalysisResult dart models"
```

---

### Task 9: API client

**Files:**
- Create: `app/mobile/lib/core/api.dart`
- Test: `app/mobile/test/api_test.dart`

**Interfaces:**
- Produces: `ChordMindApi(Dio dio, {String baseUrl})` with `Future<AnalysisResult> submit(String url)` (POST /songs), `Future<AnalysisResult> get(String youtubeId)` (GET /songs/{id}), `Future<List<({String youtubeId, String title})>> recent()`. A Riverpod `apiProvider`.
- Consumes: `AnalysisResult.fromJson` (Task 8).

- [ ] **Step 1: Write the failing test** (Dio with a mock adapter)

```dart
// app/mobile/test/api_test.dart
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

Run: `cd app/mobile && flutter test test/api_test.dart`
Expected: FAIL (api.dart not found)

- [ ] **Step 3: Write the client**

```dart
// app/mobile/lib/core/api.dart
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

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app/mobile && flutter test test/api_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/mobile && git commit -m "feat(app): ChordMind API client"
```

---

### Task 10: Chord grid sync logic + widget

**Files:**
- Create: `app/mobile/lib/features/chord_grid/grid_sync.dart`
- Create: `app/mobile/lib/features/chord_grid/chord_grid.dart`
- Test: `app/mobile/test/grid_sync_test.dart`

**Interfaces:**
- Produces: `int activeChordIndex(AnalysisResult r, double positionSeconds)` — returns the index into `synchronizedChords` whose chord is sounding at `positionSeconds` (via the `chords[]` start/end ranges), or -1 before the first chord. `ChordGrid` widget takes `AnalysisResult` + `positionSeconds` and highlights the active cell using `ChordMindColors.chordActive`.
- Consumes: `AnalysisResult` (Task 8), theme (Task 7).

- [ ] **Step 1: Write the failing test**

```dart
// app/mobile/test/grid_sync_test.dart
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

Run: `cd app/mobile && flutter test test/grid_sync_test.dart`
Expected: FAIL (grid_sync.dart not found)

- [ ] **Step 3: Write sync logic + grid widget**

```dart
// app/mobile/lib/features/chord_grid/grid_sync.dart
import 'package:chordmind/core/models.dart';

int activeChordIndex(AnalysisResult r, double pos) {
  for (var i = 0; i < r.chords.length; i++) {
    if (pos >= r.chords[i].start && pos < r.chords[i].end) return i;
  }
  return -1;
}
```

```dart
// app/mobile/lib/features/chord_grid/chord_grid.dart
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

Run: `cd app/mobile && flutter test test/grid_sync_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/mobile && git commit -m "feat(app): chord grid + sync logic"
```

---

### Task 11: Chord diagrams (guitar + piano)

**Files:**
- Create: `app/mobile/lib/features/diagrams/voicings.dart`
- Create: `app/mobile/lib/features/diagrams/guitar_diagram.dart`
- Create: `app/mobile/lib/features/diagrams/piano_diagram.dart`
- Create: `app/mobile/lib/features/diagrams/chord_diagram_sheet.dart`
- Test: `app/mobile/test/voicings_test.dart`

**Interfaces:**
- Produces:
  - `GuitarVoicing({List<int> frets, int baseFret, List<int> barres})` and `const guitarVoicings` map for common open chords (C, G, Am, F, D, E, Em, Dm). `frets` is 6 entries low→high E, `-1` = muted, `0` = open. Mirrors `reference/.../guitarVoicing.ts` shape.
  - `pianoNotes(String chord) -> List<int>` returning semitone offsets (0–11) for the chord's notes (root/third/fifth) for major & minor triads.
  - `GuitarDiagram(GuitarVoicing v)` widget; `PianoDiagram(List<int> notes)` widget; `showChordDiagram(BuildContext, String chord)` opens a bottom sheet with both (guitar shown only if a voicing exists).
- Consumes: theme (Task 7).

- [ ] **Step 1: Write the failing test**

```dart
// app/mobile/test/voicings_test.dart
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

Run: `cd app/mobile && flutter test test/voicings_test.dart`
Expected: FAIL (voicings.dart not found)

- [ ] **Step 3: Write voicings + diagram widgets**

```dart
// app/mobile/lib/features/diagrams/voicings.dart
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
// app/mobile/lib/features/diagrams/guitar_diagram.dart
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
// app/mobile/lib/features/diagrams/piano_diagram.dart
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
// app/mobile/lib/features/diagrams/chord_diagram_sheet.dart
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

Run: `cd app/mobile && flutter test test/voicings_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/mobile && git commit -m "feat(app): guitar + piano chord diagrams"
```

---

### Task 12: Player screen + routing + placeholder tabs

**Files:**
- Create: `app/mobile/lib/features/player/player_screen.dart`
- Create: `app/mobile/lib/features/home/home_screen.dart`
- Create: `app/mobile/lib/core/router.dart`
- Modify: `app/mobile/lib/main.dart`
- Test: `app/mobile/test/home_test.dart`

**Interfaces:**
- Produces:
  - `HomeScreen`: a `TextField` for a YouTube URL + "Analyze" button → calls `api.submit(url)` then routes to `/player/{youtubeId}`. Recent list below.
  - `PlayerScreen(youtubeId)`: loads analysis via `api.get`, shows the YouTube iframe player on top, `ChordGrid` below (driven by player position), and a bottom `TabBar` with tabs **Chords / Lyrics / Re-harm / Band / Versions** where the last three are placeholder `Center(Text('Coming soon'))`. Tapping a chord cell calls `showChordDiagram`.
  - `router` (go_router) with `/` and `/player/:id`.
- Consumes: `apiProvider` (Task 9), `ChordGrid` (Task 10), `showChordDiagram` (Task 11).

- [ ] **Step 1: Write the failing test** (widget test for HomeScreen renders input + button)

```dart
// app/mobile/test/home_test.dart
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

Run: `cd app/mobile && flutter test test/home_test.dart`
Expected: FAIL (home_screen.dart not found)

- [ ] **Step 3: Write home, player, router, wire main**

```dart
// app/mobile/lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:chordmind/core/api.dart';

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
      final r = await ref.read(apiProvider).submit(_ctrl.text);
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
// app/mobile/lib/features/player/player_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:chordmind/core/api.dart';
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
    ref.read(apiProvider).get(widget.youtubeId).then((r) => mounted ? setState(() => _r = r) : null);
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
// app/mobile/lib/core/router.dart
import 'package:go_router/go_router.dart';
import 'package:chordmind/features/home/home_screen.dart';
import 'package:chordmind/features/player/player_screen.dart';

final router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
  GoRoute(path: '/player/:id', builder: (_, s) => PlayerScreen(s.pathParameters['id']!)),
]);
```

```dart
// app/mobile/lib/main.dart  (replace body)
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

Run: `cd app/mobile && flutter test test/home_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/mobile && git commit -m "feat(app): home + player screens, routing, placeholder tabs"
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

Run: `cd server && python -m pytest -q && cd ../app/mobile && flutter test`
Expected: all tests PASS.

- [ ] **Step 4: Run the app on web and click through**

Run: `cd app/mobile && flutter run -d chrome` (point api baseUrl at `http://localhost:8000`)
Expected: paste a YouTube URL → Analyze → player screen with chord grid; tapping a chord cell opens the guitar+piano diagram sheet; toggling OS dark mode flips the theme.

- [ ] **Step 5: Record results + commit**

Write a short results note in `A0-VERIFY.md` (what passed, any deviations) and commit:
```bash
git add docs/superpowers/plans/A0-VERIFY.md && git commit -m "docs: A0 verification notes"
```

---

## Self-Review

**Spec coverage:** Section 1 phases → this plan is A0 (A1–A3 deferred, noted in header). Section 2 contract → Tasks 2 (server) + 8 (dart), names matched. Section 3 app modules → home (T12), player (T12), chord_grid (T10), diagrams (T11), placeholder reharm/band/versions tabs (T12), theme (T7). Section 4 server modules → api (T6), ml_worker (T5), ml_interface (T4), db Postgres (T1/T3); signaling deferred to A2 per spec. Section 5 theme → T7. Section 6 placeholders → T12 tabs + T4 stub slot. Section 7 done criteria → T13.

**Placeholder scan:** Deferred items (signaling, versioning, real models) are explicitly out of A0 scope per spec, not plan gaps. No TBD/TODO in code steps.

**Type consistency:** `AnalysisResult` field names identical across T2/T8 (`songId`, `synchronizedChords`, `beatIndex`, `timeSignature`). `activeChordIndex` signature consistent T10. `showChordDiagram(context, chord)`, `guitarVoicings`, `pianoNotes` consistent T11↔T12. `apiProvider`/`ChordMindApi.submit/get/recent` consistent T9↔T12.
