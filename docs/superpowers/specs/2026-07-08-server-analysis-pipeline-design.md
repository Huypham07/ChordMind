# Sub-project #1 — Pipeline phân tích server-side (full parity)

**Ngày:** 2026-07-08 · **Base:** `feat/song-search` · **Roadmap:** `2026-07-08-chordmind-completion-roadmap.md`

Thay `StubAnalysisSlot` bằng pipeline phân tích thật chạy server-side (cho web/desktop),
mirror `OnDeviceAnalyzer.analyze` (Dart) để web và mobile ra **cùng kết quả**. Giữ parity
bằng test tự động. Đây là linchpin: mở khóa accuracy (#5), storage, search, UI thật.

## Mục tiêu / Không mục tiêu

**Mục tiêu**
- File upload (MP3/WAV) → `AnalysisResult` JSON đúng shape hiện có, đủ để web hiển thị.
- Full parity với Dart: beat tracking + beat-sync + denoise + key, không chỉ frame-level.
- Model MVP: `btc` (mặc định) + `chordnet_2e1d` — PCM-in, vote-decode, 170 lớp.
- Parity test tự động Python↔Dart làm cổng chất lượng.

**Không mục tiêu (làm sau)**
- `chord_cnn_lstm` (hybrid CQT + XHMM 6-head).
- Nhập audio từ YouTube server-side (yt-dlp).
- Storage versioning / search / UI (sub-project #3–7).
- Mobile on-device đã có sẵn — không sửa trong #1 trừ khi parity test lộ lệch.

## Kiến trúc

Không đổi `AnalyzeSong` (cache-or-run) và shape `AnalysisResult`. Thay implementation của
port `ModelSlot`:

```
StubAnalysisSlot  →  OnnxAnalysisSlot   (server/app/infrastructure/analysis/slot.py)
```

`AnalyzeSong.execute` hiện nhận `(youtube_id, title, duration)`. Cần mở rộng để nhận **đường
file audio** cho luồng upload. Thêm tham số `audio_path: str | None` (mirror `audioFilePath`
của Dart), giữ nguyên đường YouTube (raise NotImplemented ở #1, làm ở bước sau).

### Package DSP dùng chung server-side

`server/app/infrastructure/analysis/` (thuần hàm, không phụ thuộc web/DB):

| Module | Việc | Mirror Dart | Nguồn tham chiếu |
|--------|------|-------------|------------------|
| `audio_io.py` | decode file → PCM mono float32 @ `spec.fs` (22050) | `audio_source.pcmFromFile` | librosa/ffmpeg |
| `frontend.py` | PCM → cửa sổ đầu vào model | `pcm_runner`/`hybrid_cqt` | reuse `scripts/export/cqt_frontend.py`, `ccl_frontend.py` |
| `onnx_infer.py` | onnxruntime → per-frame `(classId, confidence, time)` | `PcmInferenceRunner` | manifest `artifacts/onnx/manifest.json` |
| `beat_tracker.py` | spectral-flux onset → autocorr tempo → Ellis DP → `BeatResult(beats, bpm)` | `core/beat/{onset,tempo,beat_tracker}.dart` | reference DSP |
| `vote_decode.py` | majority filter + merge run → `List[Chord]` | `decode/vote_decode.dart` | reference `majority_filter_indices` |
| `beat_sync.py` | beat-sync chords + min-duration merge | `decode/beat_sync.dart` | — |
| `key.py` | Krumhansl key estimate | `decode/key_krumhansl.dart` | — |
| `assemble.py` | ráp JSON: chords/beats/downbeats/synchronizedChords/key/source | body của `analyze()` | — |
| `slot.py` | `OnnxAnalysisSlot(ModelSlot)` ráp tất cả | class `OnDeviceAnalyzer` | — |

Mỗi module: input/output là mảng số hoặc dataclass thuần → test độc lập, hold-in-context được.

### Luồng (mirror `OnDeviceAnalyzer.analyze`)

```
audio_path → audio_io.decode → pcm[float32]
  → onnx_infer.run(pcm, spec) → frames[(classId,conf,time)]
  → beat_tracker.track(pcm, sr) → BeatResult(beats,bpm)   (fail → BeatResult([],0))
  → beats rỗng ? vote_decode(frames,spec)
              : beat_sync(frames, beats, spec, min_chord_dur = 1.4 * median_beat_spacing)
  → key.estimate(chords)
  → assemble(...) → dict đúng AnalysisResult.fromJson
```

Hằng số giữ đúng Dart: `minChordBeats = 1.4`, `placeholderBpm = 120`, `placeholderTimeSignature = 4`,
`fallbackFrameDur = 2048/22050`, smoothing kernel mặc định 5. Fallback synthetic beat grid khi
không có beat — copy nguyên logic.

### Endpoint tối thiểu để test end-to-end

Thêm route upload trong `api/routes.py`: `POST /songs/analyze-file` (multipart file) →
lưu tạm → `AnalyzeSong.execute(..., audio_path=tmp)` → trả `AnalysisResult`. Storage/versioning
đầy đủ là #4; #1 chỉ cần đường tối thiểu để verify pipeline chạy thật.

## Bước 0 — sinh ONNX

`.onnx` bị gitignore, hiện chỉ có `manifest.json`. Trước khi code pipeline:
```
pip install -r scripts/export/requirements.txt
python -m scripts.export btc            # → artifacts/onnx/btc.onnx
python -m scripts.export chordnet_2e1d
```
Verify sha256 khớp manifest.

## Xử lý lỗi

- Decode fail (file hỏng/định dạng lạ) → lỗi 4xx rõ ràng, không 500 nuốt lỗi.
- ONNX/inference fail → raise, log, trả lỗi có ngữ cảnh (id/model).
- Beat tracker throw → fallback synthetic grid (không làm hỏng cả request), đúng như Dart.
- File tạm luôn được dọn (finally).

## Test

1. **Unit từng module** (`server/tests/analysis/`): onnx_infer shape, vote_decode merge
   (đặc biệt: đoạn quá ngắn, tie rule majority filter — mirror test Dart), beat_sync min-dur,
   key trên chuỗi chord biết trước.
2. **Parity test (cổng):** một golden clip ngắn (commit vào `server/tests/fixtures/`), chạy pipeline
   Python → so với output Dart tham chiếu (JSON snapshot sinh từ `on_device_analyzer` cho cùng clip).
   So `chords[]` (label + biên ±1 frame), `key`, `bpm`. Lệch → fail.
3. **End-to-end:** upload file qua route → 200 + JSON hợp lệ (đủ chords/beats/key).

## Definition of Done

- `OnnxAnalysisSlot` thay stub; `POST /songs/analyze-file` trả `AnalysisResult` thật từ file upload.
- Parity test Python↔Dart pass trên golden clip.
- Unit test các module pass.
- README/server cập nhật cách chạy pipeline thật + bước sinh ONNX.

## Sau #1

Chuyển sang #2 (min-duration merge denoise — verify #5) đã gần xong vì logic vote/merge nằm ngay
trong pipeline này; rồi #3 sync, #4 storage, #5 search, #6–7 UI, #8 mobile.
