# ChordMind — Song Search (DB-first → YouTube) + Uploaded-File Persistence

> Issue #2. Adds song search with two tiers — analyzed songs from the local
> store first, then a YouTube fallback — and persists uploaded audio files so
> re-opening and **re-generating** a file-based song works after its picker
> cache is gone.

## 1. Motivation

Home has two entry points (paste YouTube link, upload MP3). We need **search**:

1. **DB-first:** typing text finds already-analyzed songs by `title`
   (case-insensitive *contains*). A hit opens instantly from cache — no
   re-analysis.
2. **YouTube fallback:** no local hit (or the user taps "Search YouTube") →
   search via `youtube_explode_dart` → pick a result → open player + analyze.

Surfacing analyzed songs exposes a gap: **uploaded files aren't persisted.**
An uploaded MP3 lives only in the file-picker cache
(`.../cache/file_picker/.../x.mp3`), and its path is passed to the player via
router `extra`. Opening that song again from search (navigating by id, no
`extra`) leaves `audioFilePath == null`, so both playback and **regenerate**
(`_runGenerate`) break. So search for file songs requires persisting the
audio and recording its stable path.

## 2. Scope

**In:**
- `SongSearch` interface (swappable backend) + a default local+YouTube impl.
- `LocalStore` enumeration of stored songs.
- Persist uploaded audio to app storage; record its path on the song.
- `Source.audioPath` (nullable) so file songs carry their audio location.
- Player + regenerate use the persisted path when re-opened from search.
- Home search UI: local results first ("Đã có hợp âm"), then a YouTube
  fallback section; valid YouTube link keeps the current Analyze behavior.

**Out (deferred, YAGNI):**
- sqflite / FTS / server-side search — the `SongSearch` interface is the seam
  for that later; O(n) contains-scan is fine for a small library now.
- Deleting a song / cleaning up its persisted audio file (no delete UI yet).
- Rich result cards (thumbnails, view counts).
- Web (search UI is fine on web; analysis stays mobile-only per existing
  constraints, and YouTube search needs no analysis).

## 3. Components

### 3.1 Value types — `core/search/song_search.dart`

```dart
/// A song already in the local store (analyzed). audioPath is set for
/// uploaded-file songs, null for YouTube songs.
class StoredSong {
  final String youtubeId; // the LocalStore key id ("file:x.mp3" or a real id)
  final String title;
  final String? audioPath;
}

/// A YouTube search hit (not yet analyzed).
class YtResult {
  final String videoId;
  final String title;
  final String author;
  final Duration? duration;
}
```

### 3.2 `SongSearch` interface + `DefaultSongSearch`

```dart
abstract interface class SongSearch {
  /// Analyzed songs whose title contains [query] (case-insensitive).
  Future<List<StoredSong>> searchLocal(String query);
  /// YouTube search results for [query].
  Future<List<YtResult>> searchYoutube(String query);
}
```

`DefaultSongSearch`:
- `searchLocal` = `LocalStore.all()` filtered by
  `title.toLowerCase().contains(query.trim().toLowerCase())`; empty query →
  empty list. Trimmed, case-insensitive.
- `searchYoutube` = `YoutubeExplode().search.search(query)` mapped to
  `YtResult(v.id.value, v.title, v.author, v.duration)`; empty/whitespace
  query → empty list (no network call). The client is closed after use.

### 3.3 `LocalStore.all()`

```dart
Future<List<StoredSong>> all();
```
Reads `SharedPreferences.getKeys()`, keeps those starting with `song:v1:`,
decodes each, and returns `StoredSong(source.youtubeId, source.title,
source.audioPath)`. Skips entries that fail to decode. O(n) scan.

### 3.4 `AudioStore` — `core/audio_store.dart`

```dart
/// Copies a picked audio file into persistent app storage so it survives the
/// file-picker cache being cleared, enabling re-open and re-generate.
class AudioStore {
  /// Copies [srcPath] to <appSupport>/songs/<safeId>.<ext> and returns the
  /// stored path. safeId sanitizes the song id (e.g. "file:My Song.mp3" ->
  /// "file_My_Song_mp3"); the original extension is preserved.
  Future<String> persist(String songId, String srcPath);
}
```
Uses `path_provider`'s `getApplicationSupportDirectory()`. Creates
`songs/` if absent. Overwrites an existing copy for the same id (re-upload).

### 3.5 `Source.audioPath`

Add a nullable `audioPath` to `Source`:
```dart
final String? audioPath;
// fromJson: audioPath = j['audioPath'] as String?
```
Emitted by the analyzer/repository only for file songs; absent/null for
YouTube songs. Backward compatible (old stored JSON has no key → null).

### 3.6 Repository persists the file — `DefaultSongRepository.generate`

When `audioFilePath != null`:
1. `final stored = await audioStore.persist(youtubeId, audioFilePath);`
2. Pass the analysis through the analyzer (unchanged), then inject
   `audioPath: stored` into the saved JSON's `source` before `LocalStore.save`.

So the persisted analysis carries the stable audio path. YouTube songs are
unchanged. `AudioStore` is injected into `DefaultSongRepository` (constructor,
defaulting to `AudioStore()`), consistent with how the analyzer is injected.

### 3.7 Player uses the persisted path

`PlayerScreen` currently derives file mode from `widget.audioFilePath` (router
`extra`). Change the effective path to
`widget.audioFilePath ?? _r?.source.audioPath`:
- `_fileMode` true when either is set.
- File playback (`setFilePath`) and regenerate (`_runGenerate`) use the
  effective path.

So a file song opened from search (by id, no `extra`) loads its analysis,
reads `source.audioPath`, and plays + regenerates from the persisted copy.
(The analysis is loaded first via the existing `get()` path; file playback
initializes once the result is available.)

### 3.8 Home search UI — `features/home/home_screen.dart`

- Debounce the search field (~300ms). On non-empty text:
  - If `parseYoutubeId(text) != null` → it's a link: keep the current
    Analyze/`_analyze()` behavior (no result list).
  - Else → show **local results first**, each tagged "Đã có hợp âm"; tapping
    navigates `context.push('/player/<youtubeId>')` (no `extra` — the player
    picks up `audioPath` from the loaded result).
  - Below the local results, a **"Tìm trên YouTube"** section/button runs
    `searchYoutube`; each hit taps to `context.push('/player/<videoId>')`,
    which analyzes on demand (existing flow).
- MP3 upload + Analyze button stay.

## 4. Data flow

Upload → analyze → **persist file** → save analysis (with `audioPath`) →
later: search by title → tap → `/player/<id>` → `get()` returns cached
analysis (with `audioPath`) → play/regenerate from persisted file.

`AnalysisResult` JSON gains only the optional `source.audioPath`. All other
consumers are unaffected.

## 5. Error handling / edge cases

- **Empty/whitespace query:** both search methods return `[]` (no network).
- **YouTube search failure/offline:** `searchYoutube` surfaces the error to
  the UI (show "không tìm được", keep local results). Never crashes Home.
- **Persisted file missing at regenerate time** (user cleared app storage):
  regenerate falls back to prompting a re-pick (existing `_pickAndAnalyze`),
  rather than failing silently.
- **Corrupt stored entry:** `LocalStore.all()` skips it.
- **Duplicate title:** all matches listed; user picks.

## 6. Testing

- `LocalStore.all()`: seed mock `SharedPreferences` with 2-3 `song:v1:*`
  entries (one file song with `audioPath`, one YouTube song) → returns them;
  a malformed entry is skipped.
- `DefaultSongSearch.searchLocal`: case-insensitive contains match; non-match
  excluded; empty query → `[]`. Uses a fake/seeded `LocalStore`.
- `searchYoutube`: mapping tested behind a fake search client; empty query →
  `[]` with no network. No live network in tests.
- `AudioStore.persist`: copies a temp source file into the support dir and
  returns a path whose file exists with the same bytes; re-persist overwrites.
- `DefaultSongRepository.generate` (file mode): the saved analysis'
  `source.audioPath` points at the persisted copy (fake AudioStore).
- `Source.fromJson`: `audioPath` round-trips; absent key → null.

## 7. Scale note

O(n) contains-scan over SharedPreferences is fine for a handful of songs. The
`SongSearch` interface + `StoredSong` type isolate the backend, so moving to
sqflite (LIKE/FTS) or server search later is a `DefaultSongSearch` swap with
no UI change.
