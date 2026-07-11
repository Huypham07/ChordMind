# ChordMind server

API (FastAPI + Postgres) lưu/cache kết quả phân tích bài hát (`AnalysisResult`), quản lý
version & vote. **Web/desktop phân tích server-side** (upload file → chạy ONNX ngay trên
server); **mobile phân tích on-device**. Hai đường dùng chung một đặc tả decode/smoothing,
giữ parity (bản Python trong `app/infrastructure/analysis/` mirror pipeline Dart
`OnDeviceAnalyzer`).

## Model ONNX (bắt buộc trước khi phân tích server-side)

File `.onnx` bị gitignore — sinh từ checkpoint trong `reference/` (một lần):

```bash
pip install -r ../scripts/export/requirements.txt   # torch>=2.2,<2.9 (2.9+ dynamo exporter lỗi)
python -m scripts.export btc                          # → artifacts/onnx/btc.onnx (mặc định)
python -m scripts.export chordnet_2e1d
```

## Yêu cầu

- Python 3.12 (hoặc Docker). Postgres để chạy thật; test dùng SQLite (không cần Postgres).

## Cài đặt & chạy

```bash
python3 -m venv .venv
.venv/bin/pip install -e     ".[dev]"
.venv/bin/uvicorn app.main:app --reload          # http://localhost:8000
```

Cấu hình DB qua `DATABASE_URL` (mặc định Postgres local). Dev nhanh bằng SQLite:

```bash
DATABASE_URL=sqlite:////tmp/chordmind.db .venv/bin/uvicorn app.main:app
```

Bật Postgres: `docker compose -f ../docker-compose.infra.yml up -d`.

## Test

```bash
.venv/bin/python -m pytest -q
```

## API

| Method | Path                  | Mô tả                                                                      |
| ------ | --------------------- | -------------------------------------------------------------------------- |
| GET    | `/health`             | kiểm tra sống → `{"status":"ok"}`                                          |
| POST   | `/songs`              | body `{"url"}` (link YouTube) → `AnalysisResult` (stub; YouTube ingest chưa bật) |
| POST   | `/songs/analyze-file` | upload file audio (multipart `file`, `title`) → chạy ONNX thật → `AnalysisResult` |
| GET    | `/songs/{youtube_id}` | lấy `AnalysisResult` đã lưu, hoặc 404                                      |
| GET    | `/songs`              | danh sách bài gần đây `[{youtubeId, title}]`                               |
