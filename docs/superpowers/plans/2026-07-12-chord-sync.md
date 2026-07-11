# Chord–Audio Sync (#4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the chord highlight track the audio smoothly and consistently by interpolating the playback position between stream ticks and unifying the lead-compensation base.

**Architecture:** A pure-logic `PlaybackClock` interpolates position between real ticks; a `Ticker` in `PlayerScreen` drives `_pos` (the notifier the grid/banner already watch) from it each frame. The banner is switched to the same `chordSyncLeadSeconds` base the timeline uses.

**Tech Stack:** Dart / Flutter (`Ticker` from `package:flutter/scheduler.dart`), just_audio, youtube_player_iframe.

## Global Constraints

- Base branch: `feat/song-search`. Commit messages: plain, NO Co-Authored-By trailer.
- Client-side only (web + mobile). Do NOT touch server/pipeline or model timing.
- `_pos` (`ValueNotifier<double>` in `player_screen.dart`) stays the single notifier the chord grid + banner watch — only its *feed* changes.
- Playback rate assumed 1.0 (app has no speed control).
- `maxExtrapolation` default 1.5s (clamp so a stalled/buffering stream can't run the estimate away).
- `youtube_player_iframe` is imported with `hide PlayerState` (clashes with just_audio's `PlayerState`) — do NOT rely on the YouTube `PlayerState` enum; derive YouTube playing-state from whether the reported position advanced.
- Existing lead knob `chordSyncLeadSeconds = 0.15` (in `grid_sync.dart`) is the single calibration point; do not add a second.

---

### Task 1: PlaybackClock (pure logic + unit tests)

**Files:**
- Create: `app/lib/core/playback_clock.dart`
- Test: `app/test/core/playback_clock_test.dart`

**Interfaces:**
- Produces: `PlaybackClock({double maxExtrapolation = 1.5})`; mutable field `double duration`; `void anchor(double posSeconds, {required bool playing, DateTime? now})`; `double estimate(DateTime now)`.

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/core/playback_clock_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/playback_clock.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 0, 0, 0);
  DateTime at(double s) => t0.add(Duration(microseconds: (s * 1e6).round()));

  test('interpolates forward while playing', () {
    final c = PlaybackClock();
    c.anchor(5.0, playing: true, now: t0);
    expect(c.estimate(at(0.5)), closeTo(5.5, 1e-6));
  });

  test('frozen at anchor while paused', () {
    final c = PlaybackClock();
    c.anchor(5.0, playing: false, now: t0);
    expect(c.estimate(at(2.0)), closeTo(5.0, 1e-9));
  });

  test('new anchor re-bases (seek back allowed)', () {
    final c = PlaybackClock();
    c.anchor(30.0, playing: true, now: t0);
    c.anchor(2.0, playing: true, now: at(1.0)); // user sought backward
    expect(c.estimate(at(1.2)), closeTo(2.2, 1e-6));
  });

  test('clamps to duration', () {
    final c = PlaybackClock()..duration = 10.0;
    c.anchor(9.8, playing: true, now: t0);
    expect(c.estimate(at(1.0)), closeTo(10.0, 1e-9)); // 9.8+1.0 clamped to 10
  });

  test('clamps to maxExtrapolation when stream stalls', () {
    final c = PlaybackClock(maxExtrapolation: 1.5);
    c.anchor(5.0, playing: true, now: t0);
    expect(c.estimate(at(10.0)), closeTo(6.5, 1e-9)); // 5.0 + 1.5 cap
  });

  test('forward-only: a slightly-late now never goes below the anchor', () {
    final c = PlaybackClock();
    c.anchor(5.0, playing: true, now: t0);
    expect(c.estimate(at(-0.1)), closeTo(5.0, 1e-9));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/core/playback_clock_test.dart`
Expected: FAIL (file `playback_clock.dart` not found).

- [ ] **Step 3: Implement `playback_clock.dart`**

```dart
// app/lib/core/playback_clock.dart
/// Smooths a low-frequency / jittery playback position stream into a
/// per-frame estimate so the chord highlight tracks the audio without
/// stepping (esp. the ~1 Hz YouTube position stream). Assumes playback
/// rate 1.0.
///
/// Feed real position ticks via [anchor]; read the interpolated position via
/// [estimate] each frame.
class PlaybackClock {
  PlaybackClock({this.maxExtrapolation = 1.5});

  /// Max seconds to extrapolate past the last anchor before clamping, so a
  /// stalled/buffering stream can't run the estimate away from reality.
  final double maxExtrapolation;

  /// Song length (seconds) for the upper clamp; 0 = unknown (no clamp).
  double duration = 0;

  double _anchorPos = 0;
  DateTime? _anchorWall;
  bool _playing = false;

  /// Records a real position tick. [now] defaults to `DateTime.now()`
  /// (injectable for tests).
  void anchor(double posSeconds, {required bool playing, DateTime? now}) {
    _anchorPos = posSeconds;
    _anchorWall = now ?? DateTime.now();
    _playing = playing;
  }

  /// Interpolated position at [now]: frozen at the last anchor when paused;
  /// forward-only extrapolation while playing, clamped to [maxExtrapolation]
  /// past the anchor and to [duration].
  double estimate(DateTime now) {
    final wall = _anchorWall;
    if (wall == null || !_playing) return _clampTop(_anchorPos);
    var elapsed = now.difference(wall).inMicroseconds / 1e6;
    if (elapsed < 0) elapsed = 0; // forward-only between anchors
    if (elapsed > maxExtrapolation) elapsed = maxExtrapolation;
    return _clampTop(_anchorPos + elapsed);
  }

  double _clampTop(double v) => (duration > 0 && v > duration) ? duration : v;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/core/playback_clock_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/playback_clock.dart app/test/core/playback_clock_test.dart
git commit -m "feat(sync): PlaybackClock interpolates playback position between ticks"
```

---

### Task 2: Drive `_pos` through PlaybackClock + a Ticker

**Files:**
- Modify: `app/lib/features/player/player_screen.dart`

**Interfaces:**
- Consumes: `PlaybackClock` (Task 1).

- [ ] **Step 1: Add imports, the mixin, and fields**

In `player_screen.dart`:
- Add imports near the top:
  ```dart
  import 'package:flutter/scheduler.dart';
  import 'package:chordmind/core/playback_clock.dart';
  ```
- Change the State class declaration to provide a Ticker:
  ```dart
  class _PlayerScreenState extends ConsumerState<PlayerScreen>
      with SingleTickerProviderStateMixin {
  ```
- Add fields next to `_pos`:
  ```dart
  final _clock = PlaybackClock();
  Ticker? _ticker;
  StreamSubscription? _playingSub; // just_audio playing-state
  double _lastYtPos = -1;          // YouTube playing derived from advancement
  bool _audioPlaying = false;
  ```

- [ ] **Step 2: Start the Ticker in `initState`**

At the end of `initState` (after the existing `if (_fileMode) {...} else {...}` block, before `}`), add:

```dart
    _ticker = createTicker((_) {
      _pos.value = _clock.estimate(DateTime.now());
    })..start();
```

- [ ] **Step 3: Feed the clock from the file (just_audio) source**

In `_initFilePlayer`, replace the position subscription:

```dart
    // BEFORE:
    // _sub = player.positionStream.listen((d) => _pos.value = d.inMilliseconds / 1000.0);
    // AFTER:
    _playingSub = player.playingStream.listen((p) => _audioPlaying = p);
    _sub = player.positionStream.listen((d) {
      final pos = d.inMilliseconds / 1000.0;
      _clock.anchor(pos, playing: _audioPlaying);
      _pos.value = _clock.estimate(DateTime.now()); // floor if frames aren't pumping (tests)
    });
```

- [ ] **Step 4: Feed the clock from the YouTube source**

In `_initPlayer`, replace the `videoStateStream` subscription. YouTube's `PlayerState` enum is
hidden (import clash), so derive playing from whether the reported position advanced:

```dart
    // BEFORE:
    // _sub = _yt!.videoStateStream.listen((s) {
    //   _pos.value = s.position.inMilliseconds / 1000.0;
    // });
    // AFTER:
    _sub = _yt!.videoStateStream.listen((s) {
      final pos = s.position.inMilliseconds / 1000.0;
      final playing = pos > _lastYtPos + 1e-3; // advanced since last tick => playing
      _lastYtPos = pos;
      _clock.anchor(pos, playing: playing);
      _pos.value = _clock.estimate(DateTime.now());
    });
```

- [ ] **Step 5: Keep the clamp duration current**

Wherever `_r` is assigned (the `setState(() => _r = r)` in `_loadAnalysis` and the regenerate
path's `setState(() { ... _r = ... })`), set the clock duration right after. The simplest
single point: add a helper and call it after each `_r` assignment:

```dart
  void _syncClockDuration() {
    final d = _r?.source.duration;
    if (d != null) _clock.duration = d;
  }
```

Call `_syncClockDuration();` immediately after each place `_r` is set (inside the same
`setState` callback body is fine, or right after it). Grep for `_r = ` to find them.

- [ ] **Step 6: Dispose the Ticker and the extra subscription**

In `dispose`, add before `super.dispose()`:

```dart
    _ticker?.dispose();
    _playingSub?.cancel();
```

- [ ] **Step 7: Run the app's player/widget tests**

Run: `cd app && flutter test`
Expected: PASS. If a player widget test drove `_pos` by pumping the old direct assignment and
now reads 0, it is because frames weren't advanced — pump a frame (`await tester.pump(const
Duration(milliseconds: 16))`) OR rely on the Step-3/4 floor assignment (which already sets
`_pos` on each anchor). Do NOT weaken behavior to make a test pass; fix the test's pumping.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/player/player_screen.dart
git commit -m "feat(sync): drive chord cursor via PlaybackClock + per-frame Ticker (#4)"
```

---

### Task 3: Unify the banner's lead-compensation base

**Files:**
- Modify: `app/lib/features/chord_grid/current_chord_bar.dart`

**Interfaces:**
- Consumes: `chordSyncLeadSeconds` from `grid_sync.dart`.

- [ ] **Step 1: Apply the shared lead to the banner lookup**

In `current_chord_bar.dart`:
- Add the import:
  ```dart
  import 'package:chordmind/features/chord_grid/grid_sync.dart';
  ```
- Change the active-segment lookup (currently line ~26) to add the same lead the timeline uses:
  ```dart
    // BEFORE:
    // final i = segs.indexWhere((s) => positionSeconds >= s.start && positionSeconds < s.end);
    // AFTER: same lead base as ChordTimeline (grid_sync) so banner + timeline agree.
    final p = positionSeconds + chordSyncLeadSeconds;
    final i = segs.indexWhere((s) => p >= s.start && p < s.end);
  ```

- [ ] **Step 2: Run the tests**

Run: `cd app && flutter test`
Expected: PASS. (If a `current_chord_bar` test asserts the boundary chord at an exact position,
it must now account for the +0.15s lead; update the expected position, not the lead.)

- [ ] **Step 3: Commit**

```bash
git add app/lib/features/chord_grid/current_chord_bar.dart
git commit -m "fix(sync): banner uses same chordSyncLead base as the timeline (#4)"
```

---

## Self-Review

- **Spec coverage:** interpolation via `PlaybackClock` (Task 1) + Ticker/anchor wiring for both sources with playing-state (Task 2), duration clamp (Task 2 Step 5), banner lead unification (Task 3). Error handling: forward-only + maxExtrapolation + duration clamp (Task 1); floor `_pos` assignment for headless/test (Task 2 Steps 3–4). Manual real-feel verification is called out in the spec (not automatable). All covered.
- **Placeholder scan:** none — every code step carries full code; the "grep for `_r =`" in Task 2 Step 5 is a concrete locate instruction with the exact helper to call.
- **Type consistency:** `PlaybackClock.anchor(pos, {required bool playing, DateTime? now})`, `estimate(DateTime now)`, `duration` field, `chordSyncLeadSeconds` used consistently across tasks.
```
