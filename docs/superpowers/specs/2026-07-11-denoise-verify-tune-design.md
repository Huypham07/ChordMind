# Sub-project #2 — Verify + tune denoise (#5)

**Ngày:** 2026-07-11 · **Base:** `feat/song-search` · **Roadmap:** `2026-07-08-chordmind-completion-roadmap.md` · **Issue:** #5

Chốt rằng denoise hợp âm đã đủ, tinh chỉnh một knob có bằng chứng, và dựng cổng metric
tự động để không hồi quy — thay cho việc nghe thủ công từng lần.

## Bối cảnh đo được (measure-first)

Đo trên nhạc thật (`reference/BTC-ISMIR19/test/example.mp3`, btc model):

| Path | short_frac (<0.5s) | flicker/phút (A→B→A ngắn) |
|------|--------------------|---------------------------|
| beat-sync (mặc định, khi có beat) | **0.0** trên mọi cửa sổ 60s + toàn bài | **0.0** |
| vote (fallback, khi không có beat) | 0.136 @ minChordDur=0.3 | 0.0 |

Đường mặc định (beat-sync) đã sạch tuyệt đối — `mergeShortChords` + `minChordDur=1.4 beat`
+ majority filter đã khử hết junk/flicker. Issue #5 (D→D7→G) đã được `beat-sync-chords`
merge khắc phục từ trước; issue mở trước khi có fix.

Metric similar-alternation (A→B→A với A,B chia ≥3 nốt) đo ra 0 → không có nhiễu loại này;
`Gb↔B:maj7` chỉ chia 2 nốt (là tiến trình thật, không tune).

## Thay đổi (một, có metric biện minh)

**vote `minChordDur` mặc định 0.3 → 0.5**, áp **cả hai** bên giữ parity:
- Dart: `app/lib/core/decode/vote_decode.dart` (default `minChordDur`).
- Python: `server/app/infrastructure/analysis/vote_decode.py` (default `min_chord_dur`).

Bằng chứng sweep vote path: 0.3→short_frac 0.136; 0.4→0.05; **0.5→0.0**; 0.6→0.0 (bắt đầu
gộp quá). 0.5 = ngưỡng metric, dọn sạch đoạn <0.5s theo định nghĩa, khớp gợi ý "0.3–0.5s"
của issue #5, chưa over-merge.

Beat-sync path: **không đổi** (đã 0/0). Không thêm pass/thuật toán mới.

## Cổng metric (regression gate)

**`noise_metrics.py`** (thuần hàm, `server/app/infrastructure/analysis/`):
- `short_fraction(chords, thresh=0.5) -> float` — tỷ lệ đoạn ngắn hơn `thresh` giây.
- `flicker_per_min(chords, duration, thresh=0.5) -> float` — số A→B→A với B ngắn, trên phút.

**Test** (`server/tests/analysis/test_noise_metrics.py`):
1. Unit: metric trên chuỗi `Chord` dựng tay biết trước (đoạn ngắn kẹp, đoạn dài) → giá trị đúng.
2. Gate trên nhạc thật: decode + slice 30s đầu `reference/BTC-ISMIR19/test/example.mp3` lúc chạy
   (KHÔNG commit audio mới), chạy pipeline:
   - beat-sync path: `flicker_per_min == 0` và `short_fraction == 0`.
   - vote path (gọi trực tiếp `vote_decode` ở default mới): `short_fraction == 0`.
   Skip nếu thiếu `btc.onnx` (dùng lại guard `tests/conftest.py`) hoặc không decode được mp3.

## Ranh giới

- **Trong scope:** một knob (vote minChordDur), 2 metric hàm, gate test.
- **Ngoài scope:** đổi thuật toán decode/beat-sync; ground-truth dataset eval; xử lý
  similar-alternation (đo ra 0, cần ground-truth mới sửa an toàn); UI.

## Definition of Done

- vote `minChordDur` = 0.5 ở cả Dart + Python; test parity Dart hiện có (`vote_decode_test.dart`)
  cập nhật nếu phụ thuộc default cũ.
- `noise_metrics.py` + test: unit pass; gate trên clip thật pass (beat-sync 0/0, vote short=0).
- Full server suite xanh; skip đúng khi thiếu onnx/decoder.
- Issue #5 đóng được (denoise verified đủ + cổng chống hồi quy).
