# Sub-project #3 — Đồng bộ chord ↔ nhạc (issue #4)

**Ngày:** 2026-07-12 · **Base:** `feat/song-search` · **Roadmap:** `2026-07-08-chordmind-completion-roadmap.md` · **Issue:** #4

Làm highlight hợp âm bám sát tiếng nhạc, ổn định khi phát và khi seek — client-side Flutter,
áp cho cả web (YouTube) lẫn mobile/file.

## Bối cảnh (đọc từ code)

- `_pos` (`ValueNotifier<double>`) là điểm nghe chung của chord grid + banner.
- `_pos` được feed từ `positionStream` (just_audio, file mode) và `videoStateStream` (YouTube).
- **YouTube iframe emit ~1Hz** → highlight nhảy bậc, cảm giác giật/trễ; không interpolate giữa tick.
- Lead bù trễ `chordSyncLeadSeconds = 0.15` áp **không nhất quán**: `grid_sync.dart` có, nhưng
  `current_chord_bar.dart` (dòng 26) tự tra cứu KHÔNG bù → banner lệch timeline 0.15s.

Ba nguyên nhân issue #4: (1) tần suất cập nhật thấp; (2) không interpolate; (3) lead base không nhất quán.

## Kiến trúc

Xen một unit thuần logic `PlaybackClock` giữa stream vị trí và `_pos`. Blast radius nhỏ:
grid/banner giữ nguyên cách nghe `_pos`; chỉ đổi *nguồn feed* `_pos`.

```
positionStream / videoStateStream  +  playing-state
        → PlaybackClock.anchor(pos, playing)
   Ticker mỗi frame → PlaybackClock.estimate(now) → _pos → grid/banner (như cũ)
```

## Components

### 1. `PlaybackClock` — `app/lib/core/playback_clock.dart`
Logic thuần, inject nguồn thời gian để test được (không phụ thuộc Flutter):
- `void anchor(double posSeconds, {required bool playing, DateTime? now})` — mỗi tick stream
  gọi; ghi `(anchorPos, anchorWall, playing)`. Re-anchor mỗi event tự sửa drift.
- `double estimate(DateTime now)` — `playing ? anchorPos + (now - anchorWall) : anchorPos`.
  - **Chỉ ngoại suy tiến** (không trả về nhỏ hơn anchorPos giữa các anchor).
  - Clamp trên: không vượt `duration` (nếu biết) và không quá `anchorPos + maxExtrapolation`
    (mặc định 1.5s) để chống stream stall/buffering chạy vượt.
  - Rate giả định 1.0 (app không có speed control). ponytail: 1 knob, thêm rate nếu cần sau.
- `double get position` — giá trị estimate gần nhất (tiện đọc).
- Nhận `duration` qua constructor hoặc setter (để clamp).

### 2. Wire trong `app/lib/features/player/player_screen.dart`
- Thêm theo dõi trạng thái **playing**: just_audio `player.playingStream`; YouTube
  `s.playerState == PlayerState.playing` từ `videoStateStream`.
- Stream vị trí gọi `clock.anchor(pos, playing: ...)` thay vì gán thẳng `_pos.value`.
- Một **Ticker** (`SchedulerBinding`/`Ticker`) mỗi frame: `_pos.value = clock.estimate(DateTime.now())`.
- Pause → `playing=false` → estimate đóng băng. Seek → event vị trí re-anchor.
- Dispose Ticker cùng vòng đời hiện có (`dispose`).

### 3. Thống nhất lead — `app/lib/features/chord_grid/current_chord_bar.dart`
- Áp cùng `chordSyncLeadSeconds` như `grid_sync`: dòng tra cứu segment dùng
  `positionSeconds + chordSyncLeadSeconds` (import hằng số từ `grid_sync.dart`).
- Sau sửa: banner và timeline dùng chung một mốc thời gian.

## Error handling

- Stream stall/buffering: clamp `maxExtrapolation` giới hạn sai số; event kế re-anchor sửa.
- Headless/test (không có Ticker/YoutubeController): `_pos` vẫn nhận giá trị từ anchor trực tiếp
  (giữ đường gán trực tiếp làm fallback khi Ticker không chạy) — màn hình vẫn render.
- Seek lùi: anchor mới với pos nhỏ hơn → estimate nhảy về đúng anchor mới (re-anchor thắng
  "forward-only", vốn chỉ áp GIỮA hai anchor).

## Testing

**Unit (Dart, `app/test/core/playback_clock_test.dart`):**
1. anchor(playing) + `estimate(now+0.5s)` → ≈ anchorPos+0.5.
2. anchor(paused) + advance now → giữ nguyên anchorPos (đóng băng).
3. anchor mới → estimate bám anchor mới (sửa drift, cho phép nhảy lùi khi seek).
4. clamp: estimate không vượt `duration`; không vượt anchorPos + maxExtrapolation khi now chạy xa.
5. forward-only giữa hai anchor: now lùi nhẹ không làm estimate < anchorPos.

**Verify cảm giác thật (thủ công, cuối):** phát YouTube (web) + file (mobile/desktop), quan sát
highlight bám tiếng nhạc khi phát và sau seek. Phần "feel" không auto-gate được.

## Definition of Done

- `PlaybackClock` + unit tests pass.
- player_screen feed `_pos` qua `PlaybackClock` + Ticker; theo dõi playing-state cả 2 nguồn.
- banner dùng cùng lead → hết lệch 0.15s với timeline.
- `flutter test` xanh; app chạy được (không regression khởi tạo player).
- Issue #4 verify thủ công: highlight bám nhạc ổn định khi phát + seek.

## Ngoài scope

Speed/rate control; đổi model timing; auto-calibrate lead per-device; đụng server/pipeline.
