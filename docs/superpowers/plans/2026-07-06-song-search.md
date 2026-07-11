# Song Search (DB-first → YouTube) + Uploaded-File Persistence — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add song search (analyzed songs first, YouTube fallback) and persist uploaded audio so file-based songs can be re-opened and re-generated (issue #2).

**Architecture:** A `SongSearch` interface (local contains-scan over `LocalStore` + `youtube_explode_dart`) behind the Home UI. Uploaded audio is copied into app storage by an `AudioStore`; the persisted path is recorded on `Source.audioPath` so the player and regenerate use it when a song is re-opened by id.

**Tech Stack:** Dart / Flutter, `shared_preferences`, `path_provider`, `youtube_explode_dart` (all already dependencies), `flutter_test`.

## Global Constraints

- On-device analysis only; no new pub dependency (all listed are already in `pubspec.yaml`).
- Clean Architecture: `features/` depend on `SongRepository` / `SongSearch`, not on `LocalStore`/analyzer internals. Domain stays framework-free.
- `AnalysisResult` JSON gains only an optional `source.audioPath`; backward compatible (absent → null).
- LocalStore key prefix is `song:v1:`; each stored value is the analysis JSON with `source.{youtubeId,title,duration,bpm,timeSignature}`.
- O(n) contains-scan is acceptable now; keep the `SongSearch` seam so a sqflite/FTS/server backend can replace it without UI changes.

---

### Task 1: `Source.audioPath` (nullable) on the model

**Files:**
- Modify: `app/lib/core/models.dart` (the `Source` class)
- Test: `app/test/models_source_test.dart`

**Interfaces:**
- Produces: `Source.audioPath` (`String?`), parsed from `j['audioPath']`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models_source_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/models.dart';

Map<String, dynamic> _src({String? audioPath}) => {
      'youtubeId': 'file:a.mp3', 'title': 'A', 'duration': 1.0, 'bpm': 120.0,
      'timeSignature': 4, if (audioPath != null) 'audioPath': audioPath,
    };

void main() {
  test('Source.audioPath round-trips and defaults to null when absent', () {
    expect(Source.fromJson(_src()).audioPath, isNull);
    expect(Source.fromJson(_src(audioPath: '/x/songs/a.mp3')).audioPath,
        '/x/songs/a.mp3');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models_source_test.dart`
Expected: FAIL — `audioPath` is not defined on `Source`.

- [ ] **Step 3: Add the field**

In `app/lib/core/models.dart`, `Source`:

```dart
class Source {
  final String youtubeId, title;
  final double duration, bpm;
  final int timeSignature;
  final String? audioPath;
  Source.fromJson(Map j)
      : youtubeId = j['youtubeId'],
        title = j['title'],
        duration = (j['duration'] as num).toDouble(),
        bpm = (j['bpm'] as num).toDouble(),
        timeSignature = j['timeSignature'],
        audioPath = j['audioPath'] as String?;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/models_source_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/models.dart app/test/models_source_test.dart
git commit -m "feat(model): add nullable Source.audioPath for persisted uploads"
```

---

### Task 2: `StoredSong` + `LocalStore.all()`

**Files:**
- Create: `app/lib/core/search/song_search.dart` (value types live here; interface added in Task 4)
- Modify: `app/lib/core/local_store.dart`
- Test: `app/test/local_store_all_test.dart`

**Interfaces:**
- Produces:
  - `class StoredSong { final String youtubeId; final String title; final String? audioPath; const StoredSong(this.youtubeId, this.title, this.audioPath); }`
  - `Future<List<StoredSong>> LocalStore.all()` — every `song:v1:*` entry as a `StoredSong`, decode failures skipped.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/local_store_all_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chordmind/core/local_store.dart';

Map<String, dynamic> _analysis(String id, String title, {String? audioPath}) => {
      'songId': id, 'key': 'C major',
      'source': {
        'youtubeId': id, 'title': title, 'duration': 1.0, 'bpm': 120.0,
        'timeSignature': 4, if (audioPath != null) 'audioPath': audioPath,
      },
      'beats': [], 'downbeats': [], 'chords': [], 'synchronizedChords': [],
      'segments': [],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all() returns every stored song and skips corrupt entries', () async {
    SharedPreferences.setMockInitialValues({
      'song:v1:file:a.mp3': jsonEncode(_analysis('file:a.mp3', 'Song A', audioPath: '/s/a.mp3')),
      'song:v1:abcdefghijk': jsonEncode(_analysis('abcdefghijk', 'Song B')),
      'song:v1:corrupt': 'not json',
      'unrelated:key': 'ignored',
    });
    final all = await LocalStore().all();
    final byId = {for (final s in all) s.youtubeId: s};
    expect(byId.keys.toSet(), {'file:a.mp3', 'abcdefghijk'});
    expect(byId['file:a.mp3']!.title, 'Song A');
    expect(byId['file:a.mp3']!.audioPath, '/s/a.mp3');
    expect(byId['abcdefghijk']!.audioPath, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/local_store_all_test.dart`
Expected: FAIL — `all()` / `StoredSong` not defined.

- [ ] **Step 3: Implement**

Create `app/lib/core/search/song_search.dart`:

```dart
// app/lib/core/search/song_search.dart
//
// Search value types + interface. See docs/superpowers/specs/2026-07-06-song-search-design.md.

/// A song already in the local store (analyzed). [audioPath] is set for
/// uploaded-file songs, null for YouTube songs.
class StoredSong {
  final String youtubeId;
  final String title;
  final String? audioPath;
  const StoredSong(this.youtubeId, this.title, this.audioPath);
}

/// A YouTube search hit (not yet analyzed).
class YtResult {
  final String videoId;
  final String title;
  final String author;
  final Duration? duration;
  const YtResult(this.videoId, this.title, this.author, this.duration);
}
```

Add to `app/lib/core/local_store.dart` (import `search/song_search.dart` and `models.dart`):

```dart
/// Every stored analysis as a lightweight [StoredSong], for search/recents.
/// Corrupt entries are skipped rather than throwing.
Future<List<StoredSong>> all() async {
  final p = await SharedPreferences.getInstance();
  final out = <StoredSong>[];
  for (final key in p.getKeys()) {
    if (!key.startsWith(_prefix)) continue;
    final raw = p.getString(key);
    if (raw == null) continue;
    try {
      final src = (jsonDecode(raw) as Map)['source'] as Map;
      out.add(StoredSong(
        src['youtubeId'] as String,
        src['title'] as String,
        src['audioPath'] as String?,
      ));
    } catch (_) {
      // Skip unreadable/legacy entries.
    }
  }
  return out;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/local_store_all_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/search/song_search.dart app/lib/core/local_store.dart app/test/local_store_all_test.dart
git commit -m "feat(store): LocalStore.all() enumerates stored songs as StoredSong"
```

---

### Task 3: `AudioStore.persist()`

**Files:**
- Create: `app/lib/core/audio_store.dart`
- Test: `app/test/audio_store_test.dart`

**Interfaces:**
- Produces: `class AudioStore { Future<String> persist(String songId, String srcPath); }` — copies `srcPath` into `<appSupport>/songs/<safeId>.<ext>` and returns the stored path. Overwrites on re-persist.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/audio_store_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:chordmind/core/audio_store.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('audiostore');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('persist copies the file into <support>/songs and returns its path', () async {
    final src = File(p.join(tmp.path, 'orig.mp3'))..writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));
    final stored = await AudioStore().persist('file:My Song.mp3', src.path);

    expect(stored, startsWith(p.join(tmp.path, 'songs')));
    expect(stored, endsWith('.mp3'));
    expect(File(stored).existsSync(), isTrue);
    expect(File(stored).readAsBytesSync(), [1, 2, 3, 4]);

    // Re-persist with different bytes overwrites the same target.
    final src2 = File(p.join(tmp.path, 'orig2.mp3'))..writeAsBytesSync(Uint8List.fromList([9]));
    final stored2 = await AudioStore().persist('file:My Song.mp3', src2.path);
    expect(stored2, stored);
    expect(File(stored2).readAsBytesSync(), [9]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/audio_store_test.dart`
Expected: FAIL — `AudioStore` not defined.

- [ ] **Step 3: Implement**

```dart
// app/lib/core/audio_store.dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies picked audio into persistent app storage so uploaded songs survive
/// the file-picker cache being cleared, enabling re-open and re-generate.
/// ponytail: no eviction yet — add cleanup when a delete-song UI exists.
class AudioStore {
  /// Copies [srcPath] to <appSupport>/songs/<safeId>.<ext> and returns the
  /// stored path. The song id is sanitized to a safe filename; the source
  /// extension is preserved. Overwrites an existing copy for the same id.
  Future<String> persist(String songId, String srcPath) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'songs'));
    await dir.create(recursive: true);
    final ext = p.extension(srcPath); // includes the dot, may be empty
    final safeId = songId.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final dest = p.join(dir.path, '$safeId$ext');
    await File(srcPath).copy(dest);
    return dest;
  }
}

final audioStoreProvider = Provider((_) => AudioStore());
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/audio_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/audio_store.dart app/test/audio_store_test.dart
git commit -m "feat(store): AudioStore persists uploaded audio to app storage"
```

---

### Task 4: `SongSearch` interface + `DefaultSongSearch`

**Files:**
- Modify: `app/lib/core/search/song_search.dart` (add interface + impl)
- Test: `app/test/search/song_search_test.dart`

**Interfaces:**
- Consumes: `LocalStore.all()` (Task 2), `StoredSong`/`YtResult` (Task 2).
- Produces:
  - `abstract interface class SongSearch { Future<List<StoredSong>> searchLocal(String query); Future<List<YtResult>> searchYoutube(String query); }`
  - `class DefaultSongSearch implements SongSearch` — constructor takes a `LocalStore` and an injectable `Future<List<YtResult>> Function(String)` youtube searcher (defaulting to the real `youtube_explode_dart` call).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/search/song_search_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chordmind/core/local_store.dart';
import 'package:chordmind/core/search/song_search.dart';

Map<String, dynamic> _a(String id, String title) => {
      'songId': id, 'key': 'C major',
      'source': {'youtubeId': id, 'title': title, 'duration': 1.0, 'bpm': 120.0, 'timeSignature': 4},
      'beats': [], 'downbeats': [], 'chords': [], 'synchronizedChords': [], 'segments': [],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'song:v1:one': jsonEncode(_a('one', 'Hotel California')),
      'song:v1:two': jsonEncode(_a('two', 'california dreamin')),
      'song:v1:three': jsonEncode(_a('three', 'Yesterday')),
    });
  });

  DefaultSongSearch _search({Future<List<YtResult>> Function(String)? yt}) =>
      DefaultSongSearch(LocalStore(), youtubeSearcher: yt ?? (_) async => []);

  test('searchLocal matches title (case-insensitive, contains)', () async {
    final r = await _search().searchLocal('CALI');
    expect(r.map((s) => s.title).toSet(), {'Hotel California', 'california dreamin'});
  });

  test('searchLocal on empty/whitespace query returns nothing', () async {
    expect(await _search().searchLocal('   '), isEmpty);
  });

  test('searchYoutube delegates to the injected searcher', () async {
    final r = await _search(
      yt: (q) async => [YtResult('vid1', 'Result for $q', 'Chan', null)],
    ).searchYoutube('abba');
    expect(r.single.videoId, 'vid1');
    expect(r.single.title, 'Result for abba');
  });

  test('searchYoutube on empty query short-circuits (no searcher call)', () async {
    var called = false;
    final r = await _search(yt: (_) async { called = true; return []; }).searchYoutube('  ');
    expect(r, isEmpty);
    expect(called, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/search/song_search_test.dart`
Expected: FAIL — `SongSearch` / `DefaultSongSearch` not defined.

- [ ] **Step 3: Implement**

Append to `app/lib/core/search/song_search.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../local_store.dart';

typedef YoutubeSearcher = Future<List<YtResult>> Function(String query);

abstract interface class SongSearch {
  /// Analyzed songs whose title contains [query] (case-insensitive).
  Future<List<StoredSong>> searchLocal(String query);

  /// YouTube search results for [query].
  Future<List<YtResult>> searchYoutube(String query);
}

class DefaultSongSearch implements SongSearch {
  DefaultSongSearch(this._local, {YoutubeSearcher? youtubeSearcher})
      : _youtubeSearcher = youtubeSearcher ?? _realYoutubeSearch;

  final LocalStore _local;
  final YoutubeSearcher _youtubeSearcher;

  @override
  Future<List<StoredSong>> searchLocal(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final all = await _local.all();
    return [for (final s in all) if (s.title.toLowerCase().contains(q)) s];
  }

  @override
  Future<List<YtResult>> searchYoutube(String query) async {
    if (query.trim().isEmpty) return const [];
    return _youtubeSearcher(query);
  }
}

/// Real YouTube search via youtube_explode_dart. Closes the client after use.
Future<List<YtResult>> _realYoutubeSearch(String query) async {
  final yt = YoutubeExplode();
  try {
    final results = await yt.search.search(query);
    return [
      for (final v in results)
        YtResult(v.id.value, v.title, v.author, v.duration),
    ];
  } finally {
    yt.close();
  }
}

final songSearchProvider = Provider<SongSearch>(
    (ref) => DefaultSongSearch(ref.read(localStoreProvider)));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/search/song_search_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/search/song_search.dart app/test/search/song_search_test.dart
git commit -m "feat(search): SongSearch interface + local/YouTube DefaultSongSearch"
```

---

### Task 5: Repository persists the uploaded file + records `audioPath`

**Files:**
- Modify: `app/lib/core/song_repository.dart`
- Test: `app/test/song_repository_persist_test.dart`

**Interfaces:**
- Consumes: `AudioStore` (Task 3), existing `OnDeviceAnalyzer`, `LocalStore`.
- Produces: `DefaultSongRepository.generate` copies the picked file via `AudioStore` and injects `source.audioPath` into the saved JSON when `audioFilePath != null`. `AudioStore` is a new constructor dependency (defaulting to `AudioStore()`).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/song_repository_persist_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chordmind/core/api.dart';
import 'package:chordmind/core/audio_store.dart';
import 'package:chordmind/core/local_store.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/on_device_analyzer.dart';
import 'package:chordmind/core/song_repository.dart';

class _FakeAnalyzer extends OnDeviceAnalyzer {
  _FakeAnalyzer() : super();
  @override
  Future<Map<String, dynamic>> analyze(String youtubeId,
      {String? title, String? modelName, String? audioFilePath}) async {
    return {
      'songId': youtubeId, 'key': 'C major',
      'source': {'youtubeId': youtubeId, 'title': title ?? youtubeId, 'duration': 1.0, 'bpm': 120.0, 'timeSignature': 4},
      'beats': [], 'downbeats': [], 'chords': [], 'synchronizedChords': [], 'segments': [],
    };
  }
}

class _FakeAudioStore extends AudioStore {
  @override
  Future<String> persist(String songId, String srcPath) async => '/persisted/$songId.mp3';
}

class _ThrowingApi implements ChordMindApi {
  @override
  Future<AnalysisResult> get(String id) => throw Exception('offline');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('generate persists a file song and records source.audioPath', () async {
    final repo = DefaultSongRepository(
        _ThrowingApi(), LocalStore(), _FakeAnalyzer(), () => 'btc', _FakeAudioStore());

    final r = await repo.generate('file:x.mp3', title: 'X', audioFilePath: '/tmp/cache/x.mp3');
    expect(r.source.audioPath, '/persisted/file:x.mp3.mp3');

    // Persisted to local store too (fresh get falls back to local).
    final fetched = await repo.get('file:x.mp3');
    expect(fetched.source.audioPath, '/persisted/file:x.mp3.mp3');
  });

  test('generate for a YouTube song (no file) leaves audioPath null', () async {
    final repo = DefaultSongRepository(
        _ThrowingApi(), LocalStore(), _FakeAnalyzer(), () => 'btc', _FakeAudioStore());
    final r = await repo.generate('abcdefghijk', title: 'Y');
    expect(r.source.audioPath, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/song_repository_persist_test.dart`
Expected: FAIL — `DefaultSongRepository` has no `AudioStore` param / doesn't record `audioPath`.

- [ ] **Step 3: Implement**

In `app/lib/core/song_repository.dart`, add the `AudioStore` dependency and persist on file generate:

```dart
import 'audio_store.dart';
// ... existing imports ...

class DefaultSongRepository implements SongRepository {
  final ChordMindApi _api;
  final LocalStore _local;
  final OnDeviceAnalyzer _analyzer;
  final String Function() _selectedChordModel;
  final AudioStore _audioStore;

  DefaultSongRepository(this._api, this._local,
      [OnDeviceAnalyzer? analyzer, String Function()? selectedChordModel, AudioStore? audioStore])
      : _analyzer = analyzer ?? OnDeviceAnalyzer(),
        _selectedChordModel = selectedChordModel ?? (() => defaultModelName),
        _audioStore = audioStore ?? AudioStore();

  // get() unchanged ...

  @override
  Future<AnalysisResult> generate(String youtubeId, {String? title, String? audioFilePath}) async {
    final json = await _analyzer.analyze(youtubeId,
        title: title, modelName: _selectedChordModel(), audioFilePath: audioFilePath);
    if (audioFilePath != null) {
      final stored = await _audioStore.persist(youtubeId, audioFilePath);
      (json['source'] as Map)['audioPath'] = stored;
    }
    await _local.save(youtubeId, json);
    return AnalysisResult.fromJson(json);
  }
}
```

Update `songRepositoryProvider` to pass the audio store:

```dart
final songRepositoryProvider = Provider<SongRepository>((ref) => DefaultSongRepository(
      ref.read(apiProvider),
      ref.read(localStoreProvider),
      null,
      () => ref.read(selectedChordModelProvider),
      ref.read(audioStoreProvider),
    ));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/song_repository_persist_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/song_repository.dart app/test/song_repository_persist_test.dart
git commit -m "feat(repo): persist uploaded audio and record source.audioPath on generate"
```

---

### Task 6: Player uses `source.audioPath` when re-opened by id

The player derives file mode and regenerate from `widget.audioFilePath` (router `extra`). Fall back to the loaded result's `source.audioPath` so a file song opened from search plays and regenerates from the persisted copy. Extract the decision into a pure helper so it is unit-testable without a widget test.

**Files:**
- Modify: `app/lib/features/player/player_screen.dart`
- Create: `app/lib/features/player/effective_audio_path.dart`
- Test: `app/test/features/player/effective_audio_path_test.dart`

**Interfaces:**
- Consumes: `AnalysisResult` (`source.audioPath`).
- Produces: `String? effectiveAudioPath(String? widgetPath, AnalysisResult? result)` — returns `widgetPath` if non-null, else `result?.source.audioPath`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/player/effective_audio_path_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/features/player/effective_audio_path.dart';

AnalysisResult _r({String? audioPath}) => AnalysisResult.fromJson({
      'songId': 'file:a.mp3', 'key': 'C major',
      'source': {
        'youtubeId': 'file:a.mp3', 'title': 'A', 'duration': 1.0, 'bpm': 120.0,
        'timeSignature': 4, if (audioPath != null) 'audioPath': audioPath,
      },
      'beats': [], 'downbeats': [], 'chords': [], 'synchronizedChords': [], 'segments': [],
    });

void main() {
  test('prefers the router-provided path when present', () {
    expect(effectiveAudioPath('/picked/x.mp3', _r(audioPath: '/persisted/x.mp3')), '/picked/x.mp3');
  });
  test('falls back to the result audioPath when no router path', () {
    expect(effectiveAudioPath(null, _r(audioPath: '/persisted/x.mp3')), '/persisted/x.mp3');
  });
  test('null when neither is available', () {
    expect(effectiveAudioPath(null, _r()), isNull);
    expect(effectiveAudioPath(null, null), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/features/player/effective_audio_path_test.dart`
Expected: FAIL — `effective_audio_path.dart` not found.

- [ ] **Step 3: Implement + wire**

Create `app/lib/features/player/effective_audio_path.dart`:

```dart
import '../../core/models.dart';

/// The local audio file to play/analyze for this song: the router-provided
/// path (fresh upload) if present, else the persisted path recorded on a
/// re-opened file song's analysis.
String? effectiveAudioPath(String? widgetPath, AnalysisResult? result) =>
    widgetPath ?? result?.source.audioPath;
```

In `app/lib/features/player/player_screen.dart`, import it and replace the raw
uses of `widget.audioFilePath` for file mode / playback / regenerate with the
effective path. Add a getter and use it:

```dart
import 'effective_audio_path.dart';
// ...
String? get _audioPath => effectiveAudioPath(widget.audioFilePath, _r);
bool get _fileMode => _audioPath != null;
```

- File playback: `await player.setFilePath(_audioPath!);` (was `widget.audioFilePath!`).
- Regenerate: `Future<void> _generate() => _runGenerate(audioFilePath: _audioPath);`
- The picked-file name display (`p.basename(widget.audioFilePath!)`) should use
  `_audioPath!`.

Note: `_r` (the loaded `AnalysisResult`) must be set before file playback
initializes. If file playback is currently kicked off in `initState` for the
upload path, guard it to also run once `_r` is available for the
opened-by-id path (initialize file playback after the analysis loads when
`widget.audioFilePath == null`). Keep the existing upload path behavior
unchanged.

- [ ] **Step 4: Run test + analyze**

Run: `cd app && flutter test test/features/player/effective_audio_path_test.dart`
Expected: PASS.
Run: `cd app && flutter analyze lib/features/player/`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/player/effective_audio_path.dart app/lib/features/player/player_screen.dart app/test/features/player/effective_audio_path_test.dart
git commit -m "feat(player): play/regenerate file songs from persisted source.audioPath"
```

---

### Task 7: Home search UI (DB-first results + YouTube fallback)

**Files:**
- Modify: `app/lib/features/home/home_screen.dart`
- Test: `app/test/features/home/home_search_test.dart` (widget test — see note)

**Interfaces:**
- Consumes: `songSearchProvider` (Task 4), `parseYoutubeId` (`core/youtube.dart`), `StoredSong`/`YtResult`.
- Produces: search UI that lists local results first then a YouTube fallback section; taps navigate to `/player/<id>`.

- [ ] **Step 1: Write the failing test**

Widget tests that call `pumpAndSettle` hang in this repo's harness (see the
settings screen test). Keep this test to a single `pump()` and assert the
local-results list renders for a seeded store, with no network.

```dart
// app/test/features/home/home_search_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chordmind/core/search/song_search.dart';
import 'package:chordmind/features/home/home_screen.dart';

Map<String, dynamic> _a(String id, String title) => {
      'songId': id, 'key': 'C major',
      'source': {'youtubeId': id, 'title': title, 'duration': 1.0, 'bpm': 120.0, 'timeSignature': 4},
      'beats': [], 'downbeats': [], 'chords': [], 'synchronizedChords': [], 'segments': [],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typing a title shows the matching local song', (t) async {
    SharedPreferences.setMockInitialValues({
      'song:v1:one': jsonEncode(_a('one', 'Hotel California')),
    });
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/player/:id', builder: (_, __) => const Scaffold()),
    ]);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: router),
    ));
    await t.pump(); // let the first frame build

    await t.enterText(find.byType(TextField).first, 'hotel');
    // Debounce + async search; advance time and pump frames without settling.
    await t.pump(const Duration(milliseconds: 350));
    await t.pump();

    expect(find.text('Hotel California'), findsOneWidget);
    expect(find.text('Đã có hợp âm'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/features/home/home_search_test.dart`
Expected: FAIL — Home has no search results list yet.

- [ ] **Step 3: Implement**

In `app/lib/features/home/home_screen.dart`:
- Add search state: `String _query = ''`, `List<StoredSong> _local = []`,
  `List<YtResult> _yt = []`, `bool _searchingYt = false`, and a `Timer?
  _debounce`.
- Wire the search field's `onChanged` to set `_query` and (re)start a 300ms
  `Timer`; on fire, if `parseYoutubeId(_query) == null && _query.trim().isNotEmpty`,
  call `ref.read(songSearchProvider).searchLocal(_query)` and `setState` the
  results; clear results when the query is empty or a link.
- Render, below the search row and above "Gần đây":
  - If `_local` non-empty: a section of tappable rows, each showing the title
    and a small "Đã có hợp âm" chip; `onTap` → `context.push('/player/${s.youtubeId}')`.
  - A "Tìm trên YouTube" button; on press set `_searchingYt = true`, call
    `searchYoutube(_query)`, `setState` `_yt` (and false); render `_yt` rows,
    each `onTap` → `context.push('/player/${r.videoId}')`.
- Dispose `_debounce` in `dispose()`.
- Keep the existing link/upload/Analyze behavior when the query is a valid
  link or a file is picked.

Use the existing widgets (`AppCard`, `InfoChip`, `SearchPill`/`TextField`)
and spacing tokens; match the surrounding style. Keep the "Gần đây" section.

(Full code is left to the implementer to fit the current widget tree; the
behavior above and the test are the contract. Do not call `pumpAndSettle` in
tests; a debounced async search is exercised with explicit `pump(Duration)`.)

- [ ] **Step 4: Run test + analyze**

Run: `cd app && flutter test test/features/home/home_search_test.dart`
Expected: PASS.
Run: `cd app && flutter analyze lib/features/home/`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/home/home_screen.dart app/test/features/home/home_search_test.dart
git commit -m "feat(home): search analyzed songs (DB-first) with YouTube fallback"
```

---

## Self-Review

**Spec coverage:**
- §3.1 value types → Task 2. ✓
- §3.2 SongSearch + DefaultSongSearch → Task 4. ✓
- §3.3 LocalStore.all() → Task 2. ✓
- §3.4 AudioStore.persist → Task 3. ✓
- §3.5 Source.audioPath → Task 1. ✓
- §3.6 repository persists + records audioPath → Task 5. ✓
- §3.7 player uses audioPath → Task 6. ✓
- §3.8 Home search UI → Task 7. ✓
- §5 error handling: empty query (Task 4), corrupt entry skip (Task 2),
  missing-file regenerate re-pick (existing `_pickAndAnalyze`, unchanged in
  Task 6), YouTube failure surfaced (Task 7 UI). ✓
- §6 testing → each task's test. ✓

**Placeholder scan:** Task 7's implementation is described behaviorally (it
must fit the existing widget tree) with a concrete test contract and exact
provider/method names — not a code placeholder. All other steps show complete
code.

**Type consistency:** `StoredSong(youtubeId,title,audioPath)` and
`YtResult(videoId,title,author,duration)` defined in Task 2 and used in Tasks
4/7; `SongSearch.searchLocal/searchYoutube` (Task 4) used in Task 7;
`AudioStore.persist(songId, srcPath)` (Task 3) used in Task 5;
`Source.audioPath` (Task 1) used in Tasks 2/5/6; `effectiveAudioPath` (Task 6)
signature matches its test. `songSearchProvider`/`audioStoreProvider` names
consistent across tasks.
