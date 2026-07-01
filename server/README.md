# ChordMind server

API (FastAPI + Postgres) lưu/cache kết quả phân tích bài hát (`AnalysisResult`), quản lý
version & vote. Phân tích AI chạy trên thiết bị; server chỉ lưu (không cần GPU).

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
| POST   | `/songs`              | body `{"url"}` (link YouTube) → `AnalysisResult`; 400 nếu URL không hợp lệ |
| GET    | `/songs/{youtube_id}` | lấy `AnalysisResult` đã lưu, hoặc 404                                      |
| GET    | `/songs`              | danh sách bài gần đây `[{youtubeId, title}]`                               |
