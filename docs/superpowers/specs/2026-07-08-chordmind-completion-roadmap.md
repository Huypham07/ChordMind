# ChordMind — Roadmap hoàn thiện (2026-07-08)

Chiến lược đưa app từ "base có nhiều tồn đọng" đến chỉn chu, làm **web trước → mobile sau**,
mỗi sub-project một spec → plan → làm dứt điểm (không sửa lặt vặt rồi test lại).

## Quyết định kiến trúc (chốt)

1. **Web/desktop phân tích qua server; mobile phân tích on-device.** Cùng một đặc tả
   decode + smoothing, **hai bản triển khai giữ parity**: Python (server) & Dart (mobile).
   Sửa nhiễu/timing một lần trong đặc tả → áp cả hai bên → parity test
   (theo văn hoá `scripts/export/parity_check.py`).
2. **Server hiện là stub**: `AnalyzeSong.execute` chỉ gọi `ModelSlot.run` (port rỗng).
   Toàn bộ decode/smoothing/beat-sync đang ở Dart (`vote_decode.dart`, `core/beat/*`,
   `decode/beat_sync.dart`). Sub-project #1 = biến port này thành pipeline thật + port logic sang Python.
3. **Base = `feat/song-search`** (superset của master + app-a0): đã có beat-sync + denoise
   (#4/#5, Dart), search DB-first + YouTube fallback (#2), và persist file gốc (storage).
   Mọi sub-project xây tiếp lên nhánh này; merge master ở cuối.

## Hiện trạng đã có (đừng làm lại)

- `core/beat/{beat_tracker,onset,tempo}.dart`, `decode/beat_sync.dart` — beat tracking + beat-sync chords (có test).
- `decode/vote_decode.dart` — majority-filter smoothing mirror reference Python.
- Search: `SongSearch` + `DefaultSongSearch` (local DB-first, YouTube fallback).
- Storage: `AudioStore` persist file gốc, `Source.audioPath`, `LocalStore.all()`.
- Export: `scripts/export/*` → `artifacts/onnx/*` + manifest, có `parity_check.py`.

## Sub-projects (thứ tự)

| # | Sub-project | Issue | Trạng thái | Ghi chú |
|---|-------------|-------|-----------|---------|
| **1** | Pipeline phân tích **server-side thật** | nền #5 | stub | Nạp ONNX từ `artifacts/onnx`; port CQT/decode/beat-sync/denoise sang Python; parity test với Dart. **Linchpin.** |
| **2** | Giảm nhiễu — min-duration merge | **#5** | một phần | Thêm merge đoạn quá ngắn (<0.3–0.5s) sau majority filter, **cả Python + Dart**, giữ parity. Verify hết nhiễu rác. |
| **3** | Đồng bộ chord ↔ nhạc | **#4** | một phần | Client-side: tần suất cập nhật `_pos`, độ trễ nguồn (YouTube iframe vs just_audio), offset hiệu chỉnh. Verify khi phát + seek. |
| **4** | Storage — file gốc + kết quả versioned | — | một phần | Hoàn thiện từ nhánh: versioning kết quả, dọn/định vị file gốc, giới hạn dung lượng. |
| **5** | Search — hoàn thiện | **#2** | một phần | Review DB-first + fallback; UI search; tổ chức index. |
| **6** | UI Home redesign | **#3** | chưa | Bỏ recents giả, nối `LocalStore` thật; 3 lối vào search/link/file gọn; nhất quán theme. |
| **7** | UI dải hợp âm | **#6** | chưa | Spacing, progress-fill ô hiện tại, auto-scroll, bề rộng ∝ thời lượng. |
| **8** | Mobile on-device parity | — | — | Dùng lại đặc tả decode/smoothing; verify khớp kết quả server. |

Nhóm: **#1–2 accuracy/pipeline** → **#3–5 data/sync/search/storage** → **#6–7 UI/UX** → **#8 mobile**.

## Nguyên tắc thực thi

- Mỗi sub-project: spec riêng trong `docs/superpowers/specs/`, plan riêng, verify trước khi đóng issue.
- Không sửa nhỏ lẻ rồi test thủ công từng lần: gom theo sub-project, có test tự động (parity/unit) làm cổng.
- Logic dùng chung Python↔Dart luôn đi kèm parity test.

## Kế tiếp

Brainstorm chi tiết **sub-project #1** (pipeline server-side) thành spec đầy đủ để bắt tay code.
