# ChordMind — Thiết kế tổng thể (Design Spec)

> Ngày: 2026-06-29
> Trạng thái: Draft để duyệt
> Phạm vi: Nền tảng âm nhạc cộng tác real-time + Edge AI sinh/biến tấu hợp âm.
> Hai track song song: **(1) Models** và **(2) App**, ghép qua một interface chung.

---

## 0. Tóm tắt điều hành (Executive Summary)

ChordMind là nền tảng cho người chơi nhạc / ban nhạc không chuyên, kết hợp:

1. **Phân tích bài hát tự động** (beat, key, chord, segmentation, melody) — chạy 1 lần trên server, cache lại, tái sử dụng cho cộng đồng ("Wikipedia hợp âm").
2. **Edge AI on-device** — sinh/biến tấu vòng hợp âm (đổi tone, đổi style Jazz/Pop) bằng model đã lượng hóa (TFLite/ONNX), không tốn server.
3. **Đồng bộ ban nhạc real-time** — WebRTC DataChannel + Ableton Link, truyền tín hiệu nhạc lý JSON siêu nhẹ thay vì audio.

Đóng góp học thuật được phân thành 3 hướng, **Hướng 1 là trục chính**:

- **H1 (trục chính):** Edge-ACR + Generative Re-harmonization on-device — nén/lượng hóa model ACR chạy real-time gần như không giảm độ chính xác, + model sinh/biến tấu hợp âm có điều kiện (supervised).
- **H2 (nhánh thực nghiệm):** Dùng **MuQ** (music foundation model SSL) làm backbone feature thay CQT thủ công cho ACR, đo cải thiện trên rare chords.
- **H3 (systems của app):** Đồng bộ cộng tác real-time (WebRTC + Ableton Link + latency compensation + versioning kiểu CRDT/upvote).

Tất cả các hướng đều triển khai đầy đủ. Tài nguyên/thời gian không phải ràng buộc; ưu tiên chất lượng và đóng góp học thuật rõ ràng.

---

## 1. Bối cảnh & tài liệu tham chiếu

| Nguồn | Vai trò | Ghi chú |
|---|---|---|
| `research_proposal.md` | Ý tưởng gốc của tác giả | Edge AI + band sync + crowdsource |
| `reference/arXiv-2602.19778v3/DAFx26_tmpl.tex` | Paper ChordMini (Phan et al. 2026) | Pseudo-label + KD 2-stage cho ACR |
| `reference/ChordMini/` | Code paper (ChordNet 2E1D + BTC) | Có checkpoint |
| `reference/ChordMiniApp/` | Web app tham khảo (Next.js + Flask) | Ghép sẵn nhiều model |
| `reference/BTC-ISMIR19/` | BTC gốc (Park et al. 2019) | Teacher model |
| `reference/chord-cnn-lstm-model/` | Large-voca chord (ISMIR2019) | Tác giả app đánh giá tốt nhất cho chord |
| `reference/MuQ/` | Music foundation model SSL | Backbone cho H2 |
| `reference/model_checkpoints/` | Checkpoint người dùng đã tải | `BTC/btc_model_best.pth`, `ChordNet/student_model_best.pth` |

### Checkpoint sẵn có (đã xác minh trên đĩa)
- `reference/ChordMini/checkpoints/btc_model_best.pth` (≈36 MB) — BTC CL (full).
- `reference/ChordMini/checkpoints/2e1d_model_best.pth` (≈27 MB) — ChordNet (2E1D) CL (full).
- `reference/ChordMini/checkpoints/btc_model_large_voca.pt` (≈12 MB) — BTC teacher gốc.
- `reference/model_checkpoints/BTC/btc_model_best.pth`, `reference/model_checkpoints/ChordNet/student_model_best.pth`.

### Số liệu tham chiếu (từ paper, test set 120 bài, clean labels)
| Model | Root | Thirds | Triads | 7ths | Tetrads | Majmin | MIREX |
|---|---|---|---|---|---|---|---|
| BTC teacher (pretrained) | 81.95 | 78.46 | 76.75 | 66.51 | 63.85 | 78.98 | 78.41 |
| BTC student All (3.03M) | 81.54 | 77.86 | 76.08 | 66.29 | 63.54 | 78.29 | 77.84 |
| 2E1D student All (2.2M) | 80.37 | 76.63 | 74.91 | 64.37 | 61.50 | 77.29 | 76.35 |

> Đây là baseline cần tái lập trước khi cải tiến. Mục tiêu H1/H2 là vượt các số này (đặc biệt rare chords: 7ths/Tetrads/ACQA) và/hoặc giữ ~99% sau lượng hóa.

---

## 2. Pipeline kỹ thuật (luồng xử lý một bài hát)

Mỗi bước là một "slot model" — app gọi qua interface, model thay được mà không sửa app.

```
audio ─┬─[1] source separation (tùy chọn, cho beat) ─ Demucs/Spleeter
       ├─[2] beat & downbeat ───────────────────────── Beat-Transformer / madmom
       ├─[3] chord recognition ───────────────────────  chord-cnn-lstm / BTC / ChordNet(2E1D)
       ├─[4] key detection ──────────────────────────── Gemini / krumhansl / madmom
       ├─[5] segmentation (intro/verse/chorus) ──────── SongFormer
       └─[6] melody transcription (experimental) ────── SheetSage
                          │
                          ▼ (kết quả → JSON chuẩn, cache server)
       [7] ★ re-harmonization / sinh hợp âm có điều kiện (on-device, novelty H1)
       [8] ★ sinh tiếng đàn đệm / accompaniment (novelty H1)
       [9] ★ edge quantization (novelty H1) — áp cho bước 3 & 7
      [10] ◇ MuQ backbone thay CQT cho bước 3 (nhánh thực nghiệm H2)
```

### Bảng model chi tiết

| # | Bước | Model ưu tiên → thay thế | Kết quả/ghi chú đã có | Loại đóng góp |
|---|---|---|---|---|
| 1 | Source separation | Demucs v4 → Spleeter | Beat-Transformer cần spleeter (app note Windows khó cài) | reuse |
| 2 | Beat/downbeat | Beat-Transformer → madmom | Beat-Transformer SOTA F~0.87 trên các test set chuẩn | reuse |
| 3 | Chord recognition | **chord-cnn-lstm (large-voca)** → BTC-CL → ChordNet 2E1D | xem bảng §1; có đủ 3 checkpoint | reuse + cải tiến (H2) |
| 4 | Key detection | Gemini API → krumhansl-schmuckler | App dùng Gemini cho roman numeral + enharmonic | reuse |
| 5 | Segmentation | SongFormer | Có Docker service trong app | reuse |
| 6 | Melody | SheetSage | App đánh dấu experimental, chậm | reuse (optional) |
| 7 | **Re-harmonization** | Transformer/VAE có điều kiện (tone/style), supervised | **chưa có — tự build** | **novelty H1** |
| 8 | **Accompaniment** | rule-based MIDI → MusicVAE / Anticipatory Music Transformer (supervised) | **chưa có — tự build** | **novelty H1** |
| 9 | **Edge quantization** | distill → ONNX → TFLite INT8 + benchmark acc/latency | **chưa có — tự build** | **novelty H1** |
| 10 | **MuQ backbone** | MuQ embedding thay CQT làm input bước 3 | MuQ SOTA MARBLE; pip `muq`, auto HF | **nhánh H2** |

### Phương pháp huấn luyện bước 7-8 (generative)
- Cả hai dùng **supervised** (teacher forcing) trên Hooktheory/Chordonomicon (re-harmonization) và Lakh MIDI (accompaniment).
- Điều kiện hóa: tone đích, style (Jazz/Pop), độ phức tạp. Đánh giá bằng metric nhạc lý + user study (§5). Không dùng RL.

---

## 3. Dataset — kế hoạch tải

### Tải tự động được (sẽ viết `scripts/download_datasets.py`)
| Dataset | Dùng cho | Nguồn |
|---|---|---|
| FMA (small/medium/large) | pseudo-label, beat | mirdata / Zenodo |
| MAESTRO v3 | pseudo-label (piano) | magenta storage |
| MuQ weights | backbone H2 | HuggingFace `OpenMuQ` (auto) |
| Lakh MIDI (LMD) | accompaniment | colinraffel.com / HF |
| Hooktheory / Chordonomicon | re-harmonization | HuggingFace |
| Ballroom / GTZAN / Hainsworth | eval beat | mirdata |
| Harmonix / SALAMI | eval segmentation | mirdata / Zenodo |

### Phải tự xin/tự tải (chỉ có nhãn, audio bản quyền)
| Dataset | Lý do | Ghi chú |
|---|---|---|
| Isophonics | audio bản quyền | nhãn tải được tại isophonics.net |
| McGill Billboard | audio bản quyền | nhãn tại ddmal |
| RWC-Pop | license riêng | phải đăng ký RWC |
| USPop2002 | audio bản quyền | nhãn tại github tmc323/Chord-Annotations |
| DALI | audio theo link YouTube | metadata + nhãn tải được, audio tự crawl |

> Roadmap sẽ ghi rõ link + cách lấy từng cái. Script chỉ tải phần hợp pháp/tự động; phần còn lại in hướng dẫn.

---

## 4. Kiến trúc 3 phần (App = mobile + server tách lớp)

> Quyết định kiến trúc đã chốt: **backend tách lớp, host trên server**, KHÔNG nhúng vào app. Lý do: cần shared state cho version/upvote, signaling cho WebRTC, và pipeline nặng chạy 1 lần/bài. Edge AI nhẹ chạy on-device.

```
┌─────────────────────────────┐        ┌──────────────────────────────────────┐
│  app/mobile (Flutter)        │        │  server/ (VPS hoặc Cloud Run)          │
│  - UI: player, chord grid,   │  HTTPS │  ┌─ api/        FastAPI: version CRUD, │
│    piano/guitar, lyrics      │◄──────►│  │              JSON store, auth        │
│  - Edge AI (TFLite/ONNX):    │  WSS   │  ├─ signaling/  WebRTC signaling (WS)  │
│    re-harmonization on-device│◄──────►│  └─ ml_worker/  pipeline nặng (1 lần/  │
│  - WebRTC P2P + Ableton Link │        │                 bài) → cache           │
└─────────────────────────────┘        └──────────────────────────────────────┘
        ▲   P2P DataChannel (JSON clock sync)   ▲                  │
        └───────────────────────────────────────┘                 ▼
                                                          db/ (Firestore/Postgres):
                                                          songs, versions, votes
```

### Track 1 — Models (Kaggle/Colab notebooks)
```
models/
  notebooks/    # mỗi bước 1 notebook: train/finetune/eval/quantize
  src/          # reuse code từ reference (chord-cnn-lstm, ChordMini, MuQ)
  checkpoints/  # checkpoint hiện có + bản quantized
  export/       # ONNX / TFLite — artifact để app lắp
  eval/         # mir_eval scripts, bảng tái lập paper + bảng cải tiến
```
Quy trình mỗi model: **tái lập baseline → cải tiến (MuQ/KD/RL) → eval mir_eval → quantize → export → ghi bảng số**.

### Track 2 — App (khung "lắp model")
```
app/mobile/        # Flutter đa nền tảng
  ├─ ui/             player, chord grid, piano/guitar diagram, lyrics
  ├─ edge/           TFLite runtime: re-harmonization on-device
  └─ sync/           WebRTC DataChannel + Ableton Link + latency compensation
server/
  ├─ api/            FastAPI: version CRUD, JSON store, auth, upvote
  ├─ signaling/      WebSocket signaling cho WebRTC
  ├─ ml_worker/      chạy pipeline nặng bước 1-6 khi upload bài mới
  └─ ml_interface/   ★ HỢP ĐỒNG I/O: ModelSlot(beat/chord/key/segment/melody/gen)
db/                  # schema: songs, versions, votes, users
```

### `ml_interface` — điểm ghép 2 track
- Định nghĩa hợp đồng I/O chuẩn (vd `audio bytes → AnalysisResult{beats[], chords[], key, segments[], melody?}` dạng JSON schema cố định).
- Track 1 nhả checkpoint/ONNX đúng hợp đồng → cắm vào `ml_worker` không sửa app.
- Cho phép 2 track phát triển độc lập, không chặn nhau.

---

## 5. Thực nghiệm & metric đánh giá

| Hạng mục | Metric | Công cụ |
|---|---|---|
| ACR (bước 3, H2) | Root/Thirds/Triads/7ths/Tetrads/Majmin/MIREX, WCSR, **ACQA** (rare chords) | `mir_eval` |
| Beat | F-measure, CMLt, AMLt | `mir_eval.beat` |
| Segmentation | Over/Under/Seg | theo công thức paper |
| Edge quantization (H1) | Δaccuracy vs FP32, **latency on-device (ms)**, model size (MB), RAM | benchmark thiết bị thật |
| Re-harmonization (H1) | music-theory consistency score, style classification acc, **user study (MOS)** | rule-based + người dùng |
| Sync (H3) | độ lệch phách (ms), băng thông (KB/s) | đo thực nghiệm |

---

## 6. Lộ trình phase (tham chiếu nhanh; chi tiết ở `ROADMAP_LEARNING.md`)

**Track Model:** P0 nền tảng DSP/CQT/mir_eval → P1 tái lập ACR baseline (3 model) → P2 MuQ backbone (H2) → P3 generative supervised (H1 bước 7-8) → P4 edge quantization (H1 bước 9).

**Track App (song song):** A0 khung Flutter + FastAPI + db schema → A1 `ml_interface` + ml_worker (cắm model bước 1-6) → A2 WebRTC + Ableton Link (H3) → A3 versioning + upvote ("Wikipedia hợp âm").

**Ghép:** sau P4 & A1, export model → cắm vào `ml_worker`/`edge`.

---

## 7. Rủi ro & giảm thiểu

| Rủi ro | Mức | Giảm thiểu |
|---|---|---|
| Audio dataset bản quyền (Isophonics/RWC/USPop) khó lấy | Cao | Tận dụng pseudo-label trên FMA/DALI/MAESTRO (đúng method paper); ghi rõ nguồn nhãn |
| AMD GPU local khó train (ROCm) | TB | Ưu tiên Kaggle/Colab cho train; local chỉ inference/dev |
| Edge quantization giảm accuracy nhiều | TB | So distill vs PTQ vs QAT; giữ ngưỡng ~99% teacher |
| Ableton Link tích hợp Flutter (SDK C++) | TB | Viết platform channel; fallback WebRTC clock sync thuần |
| Scope quá lớn | Cao | 2 track song song, mỗi phase có tiêu chí "done" rõ; ghép sau |

---

## 8. Deliverable của giai đoạn brainstorm này

1. `research_proposal.md` — mở rộng chi tiết (giữ ý gốc, thêm: đóng góp H1/H2/H3, pipeline §2, phương pháp từng novelty, thực nghiệm §5, dataset §3, rủi ro §7).
2. `ROADMAP_LEARNING.md` — lộ trình học theo phase, mỗi phase: kiến thức cần học, paper/khóa/repo tham khảo, tiêu chí done.
3. `scripts/download_datasets.py` — tải phần tự động được + in hướng dẫn phần tự tải.

> Lưu ý: thư mục `D:\code\ChordMind` hiện **không phải git repo**, nên spec này không được commit. Nếu muốn, có thể `git init` để theo dõi version các deliverable.
