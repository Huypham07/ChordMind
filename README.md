# ChordMind

Nền tảng âm nhạc cộng tác cho người chơi nhạc / ban nhạc không chuyên.

## Chức năng

- Nhập link YouTube → hiển thị **hợp âm tự động** đồng bộ theo nhạc, kèm **thế bấm** guitar & piano.
- Mô hình "Wikipedia hợp âm": mỗi bài phân tích một lần, lưu lại và dùng chung cho cộng đồng.
- Biến tấu vòng hợp âm bằng AI **trên thiết bị** (đổi tone / style) — *đang phát triển*.
- Đồng bộ ban nhạc real-time qua WebRTC + Ableton Link — *đang phát triển*.
- Giao diện sáng/tối, mobile-first; **web/desktop** phân tích server-side (upload file), **mobile** phân tích on-device.

> Web/desktop gọi server chạy ONNX; mobile chạy on-device. Hai đường giữ parity (decode/smoothing chung một đặc tả). Xem `server/README.md` (bước sinh ONNX + `POST /songs/analyze-file`).
> Thiết kế & kiến trúc chi tiết: `docs/superpowers/specs/` · kế hoạch: `docs/superpowers/plans/`.

## Yêu cầu

- Docker (chạy nhanh) **hoặc** Python 3.12 + Flutter 3.x (chạy dev).

## Chạy bằng Docker

```bash
# 1) hạ tầng (Postgres) — chạy trước, tạo network "chordmind"
docker compose -f docker-compose.infra.yml up -d

# 2) build web bundle (image web dùng bản này)
cd app && flutter build web && cd ..

# 3) app stack — API tại :8000, web tại :8080
docker compose -f docker-compose.app.yml up --build
```

## Chạy dev (không Docker)

```bash
# server  → http://localhost:8000
cd server && python3 -m venv .venv && .venv/bin/pip install -e ".[dev]"
.venv/bin/uvicorn app.main:app --reload

# app (web để test, hoặc -d <device> cho mobile)
cd app && flutter pub get && flutter run -d chrome
```

Chi tiết từng phần: `server/README.md`, `app/README.md`.

## Model export (base pipeline)

Convert reference chord checkpoints to on-device ONNX:

```bash
pip install -r scripts/export/requirements.txt
python -m scripts.export chordnet_2e1d   # -> artifacts/onnx/{chordnet_2e1d.onnx,manifest.json}
```

## Trạng thái

- **A0 (xong):** nhập YouTube → hiển thị chord grid + thế bấm + theme.
- **Phân tích thật (xong):** pipeline ONNX on-device (mobile) + server-side (web/desktop, `POST /songs/analyze-file`), parity Python↔Dart.
- **A1 / A2 / A3** (model thật on-device, đồng bộ ban nhạc, versioning + vote): đang theo lộ trình.
