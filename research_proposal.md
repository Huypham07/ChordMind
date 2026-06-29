# ĐỀ CƯƠNG DỰ ÁN ChordMind: NỀN TẢNG ÂM NHẠC CỘNG TÁC THỜI GIAN THỰC & AI SINH HỢP ÂM

_(Real-time Collaborative Music & Edge-AI Chord Platform)_

> Phiên bản chi tiết — 2026-06-29. Xem thiết kế kỹ thuật đầy đủ tại
> `docs/superpowers/specs/2026-06-29-chordmind-design.md` và lộ trình học tại
> `ROADMAP_LEARNING.md`.

---

## 1. Tầm nhìn & Ý tưởng cốt lõi (Core Concept)

Xây dựng một ứng dụng di động (hướng tới đa nền tảng hiệu năng cao) dành cho người chơi nhạc và các ban nhạc không chuyên, kết hợp giữa mô hình **"Wikipedia cho hợp âm"** (Crowdsourcing) và **Công nghệ AI trên thiết bị (Edge AI)**.

Ứng dụng không chỉ cung cấp hợp âm tự động chuẩn xác cho các bài hát đầu vào mà còn giải quyết triệt để nỗi đau của giới chơi nhạc: **Đồng bộ hóa thời gian thực cho ban nhạc (Band Synchronization) với độ trễ cực thấp.**

---

## 2. Đóng góp học thuật (Academic Contributions)

Paper tham chiếu chính (ChordMini — Phan et al., DAFx 2026, arXiv:2602.19778) đã đóng góp ở mảng *cách huấn luyện* mô hình nhận diện hợp âm (pseudo-label + knowledge distillation 2 giai đoạn). Để tránh trùng lặp và tạo đóng góp mới, dự án định vị 3 hướng, **H1 là trục chính**:

### H1 (Trục chính) — Edge-ACR + Generative Re-harmonization on-device
- **H1a:** Nén/lượng hóa (distillation → pruning → quantization PTQ/QAT) mô hình nhận diện hợp âm để chạy real-time **trên thiết bị di động**, giữ độ chính xác ≈99% so với mô hình gốc. Đóng góp = phân tích đánh đổi accuracy ↔ latency ↔ kích thước trên phần cứng thật. *Chưa repo nào trong tham chiếu làm điều này.*
- **H1b:** Một mô hình **sinh / biến tấu vòng hợp âm có điều kiện** (đổi tone, đổi style Jazz/Pop, độ phức tạp) chạy on-device, huấn luyện **supervised**. Đánh giá bằng metric nhạc lý + user study.

### H2 (Nhánh thực nghiệm) — Foundation-model backbone cho ACR
- Thay đặc trưng CQT thủ công bằng embedding từ **MuQ** (mô hình nền âm nhạc SSL, SOTA trên MARBLE) làm đầu vào cho bộ nhận diện hợp âm. Mục tiêu: chứng minh foundation embedding cải thiện ACR, đặc biệt trên **hợp âm hiếm** (7ths/Tetrads/ACQA).

### H3 (Systems của app) — Đồng bộ cộng tác real-time
- Đóng góp kỹ thuật hệ thống: WebRTC DataChannel + Ableton Link + thuật toán bù trừ độ trễ + cơ chế versioning kiểu CRDT/upvote cho "Wikipedia hợp âm".

> Cả ba hướng đều được triển khai đầy đủ. Trục chính để viết paper/luận văn là H1; H2 là thực nghiệm tăng chất lượng; H3 là phần hệ thống của sản phẩm.

---

## 3. Luồng hoạt động hệ thống (System Workflow)

Hệ thống vận hành theo cơ chế phân tán, giảm thiểu tối đa gánh nặng cho máy chủ:

- **Bước 1 (Khởi tạo):** User A tải lên/quét một bài hát mới. **Server (`ml_worker`)** chạy các mô hình AI để phân tích cấu trúc, nhịp, hợp âm và lưu trữ có cấu trúc, có quản lý version global.
- **Bước 2 (Tái sử dụng):** User B quét đúng bài hát đó. Server chỉ cần trả về các version đã được tạo (cache).
- **Bước 3 (Biến tấu nội bộ):** User B có thể:
  - Chỉnh sửa thủ công các hợp âm bị sai.
  - Kích hoạt **AI cục bộ (On-device AI)** trên điện thoại để sinh lại vòng hợp âm theo phong cách khác (Jazz, Pop, đổi Tone) dựa trên khung dữ liệu có sẵn (H1b).
- **Bước 4 (Đóng góp):** Bản chỉnh sửa/sinh mới của User B được đồng bộ lên Server thành một `Version` mới. Cộng đồng Upvote/Downvote để chọn bản chuẩn nhất (Default Version).

---

## 4. Pipeline kỹ thuật xử lý một bài hát

Mỗi bước là một "slot model" — app gọi qua interface chuẩn, mô hình thay được mà không sửa app.

```
audio ─┬─[1] source separation (tùy chọn) ─ Demucs/Spleeter
       ├─[2] beat & downbeat ────────────── Beat-Transformer / madmom
       ├─[3] chord recognition ──────────── chord-cnn-lstm / BTC / ChordNet(2E1D)
       ├─[4] key detection ───────────────── Gemini / krumhansl
       ├─[5] segmentation ────────────────── SongFormer
       └─[6] melody (experimental) ───────── SheetSage
                          │  → JSON chuẩn, cache server
       [7] ★ re-harmonization (on-device, H1b)
       [8] ★ accompaniment / sinh đàn đệm (H1b)
       [9] ★ edge quantization (H1a, áp cho bước 3 & 7)
      [10] ◇ MuQ backbone thay CQT cho bước 3 (nhánh H2)
```

### Mô hình & kết quả tham chiếu đã có

Số liệu ACR từ paper (test set 120 bài, clean labels):

| Model | Root | Thirds | Triads | 7ths | Tetrads | Majmin | MIREX |
|---|---|---|---|---|---|---|---|
| BTC teacher (pretrained) | 81.95 | 78.46 | 76.75 | 66.51 | 63.85 | 78.98 | 78.41 |
| BTC student All (3.03M) | 81.54 | 77.86 | 76.08 | 66.29 | 63.54 | 78.29 | 77.84 |
| 2E1D student All (2.2M) | 80.37 | 76.63 | 74.91 | 64.37 | 61.50 | 77.29 | 76.35 |

Checkpoint đã có sẵn (trong `reference/`):
- `ChordMini/checkpoints/btc_model_best.pth` — BTC CL (full).
- `ChordMini/checkpoints/2e1d_model_best.pth` — ChordNet (2E1D) CL (full).
- `ChordMini/checkpoints/btc_model_large_voca.pt` — BTC teacher gốc.
- `model_checkpoints/BTC/btc_model_best.pth`, `model_checkpoints/ChordNet/student_model_best.pth`.

> Tác giả ChordMiniApp đánh giá **chord-cnn-lstm (large-voca)** cho chất lượng chord tổng thể tốt; sẽ dùng làm baseline ưu tiên cho bước 3, đối chiếu BTC và ChordNet.

### Phương pháp huấn luyện bước 7-8 (generative, supervised)
- Re-harmonization: huấn luyện trên Hooktheory/Chordonomicon, điều kiện hóa tone đích + style + độ phức tạp.
- Accompaniment: huấn luyện trên Lakh MIDI (rule-based MIDI làm baseline → MusicVAE / Anticipatory Music Transformer).
- Đánh giá: metric nhạc lý (voice-leading, hòa thanh chức năng) + user study (MOS). Không dùng RL.

---

## 5. Các bài toán kỹ thuật & Giải pháp đề xuất

### Bài toán 1: Tối ưu chi phí & gánh tải Server

- **Vấn đề:** Chạy AI xử lý âm thanh trên server cho hàng ngàn người dùng sẽ tốn chi phí khổng lồ.
- **Giải pháp:** Server từ bỏ vai trò "tính toán nặng liên tục" để trở thành "người điều phối" (quản lý Version, DB JSON, Signaling). Pipeline nặng (bước 1-6) chỉ chạy **1 lần/bài** trong `ml_worker` rồi cache. Các tác vụ AI biến tấu hợp âm (H1b) đẩy về thiết bị qua mô hình lượng hóa (Quantized — TFLite/ONNX).

### Bài toán 2: Đồng bộ ban nhạc thời gian thực (trễ & băng thông)

- **Vấn đề:** Chơi nhạc chung online/offline thường bị lệch phách do độ trễ mạng (Ping) và tốn dữ liệu nếu truyền luồng âm thanh.
- **Giải pháp:** Dùng **WebRTC (DataChannel)** kết nối trực tiếp (Peer-to-Peer). Chỉ truyền "Tín hiệu đồng bộ lệnh nhạc lý" (MIDI-like Clock Sync) định dạng JSON siêu nhẹ thay vì truyền Audio. Áp dụng thuật toán bù trừ độ trễ (Latency Compensation).
  - **Ableton Link (quan trọng nhất):** công nghệ mã nguồn mở chuẩn ngành để đồng bộ nhịp (BPM/Tempo) giữa các thiết bị qua Wi-Fi, có sẵn SDK Android/C++. Tự xử lý đồng bộ thời gian + bù trừ độ trễ để các thiết bị nện đúng phách. Tích hợp vào Flutter qua platform channel; fallback WebRTC clock sync thuần nếu Link không khả dụng.

### Bài toán 3: Edge AI lượng hóa (H1a)

- **Vấn đề:** Mô hình ACR/generative gốc quá nặng để chạy real-time trên điện thoại.
- **Giải pháp:** Pipeline nén: distillation → pruning → quantization (PTQ rồi QAT nếu cần) → export ONNX/TFLite INT8. Benchmark accuracy ↔ latency ↔ size trên thiết bị thật.

---

## 6. Kiến trúc hệ thống (3 phần)

```
app/mobile (Flutter)            server/ (VPS / Cloud Run)
- UI player, chord grid,        - api/        FastAPI: version CRUD, JSON, auth, vote
  piano/guitar, lyrics          - signaling/  WebRTC signaling (WebSocket)
- Edge AI (TFLite): H1b         - ml_worker/  pipeline nặng bước 1-6 (1 lần/bài) → cache
- WebRTC P2P + Ableton Link     - ml_interface/ HỢP ĐỒNG I/O cho mọi ModelSlot
                                db/  songs, versions, votes, users
```

Hai track phát triển song song và ghép qua `ml_interface`:
- **Track Model:** notebook Kaggle/Colab → checkpoint → quantize → export ONNX/TFLite.
- **Track App:** khung Flutter + server, cắm artifact của Track Model vào `ml_worker`/`edge`.

---

## 7. Thực nghiệm & metric

| Hạng mục | Metric | Công cụ |
|---|---|---|
| ACR (bước 3, H2) | Root/Thirds/Triads/7ths/Tetrads/Majmin/MIREX, WCSR, ACQA | `mir_eval` |
| Beat | F-measure, CMLt, AMLt | `mir_eval.beat` |
| Segmentation | Over/Under/Seg | công thức paper |
| Edge (H1a) | Δaccuracy vs FP32, latency on-device (ms), size (MB), RAM | thiết bị thật |
| Re-harmonization (H1b) | music-theory consistency, style acc, user study (MOS) | rule + người dùng |
| Sync (H3) | độ lệch phách (ms), băng thông (KB/s) | đo thực nghiệm |

---

## 8. Kế hoạch dataset

**Tải tự động** (script `scripts/download_datasets.py`): FMA, MAESTRO, MuQ weights (HF), Lakh MIDI, Hooktheory/Chordonomicon, các test set beat (Ballroom/GTZAN/Hainsworth) và segmentation (Harmonix/SALAMI).

**Phải tự xin/tự tải (audio bản quyền, chỉ có nhãn):** Isophonics, McGill Billboard, RWC-Pop, USPop2002, DALI. Hướng dẫn chi tiết trong `ROADMAP_LEARNING.md`.

---

## 9. Rủi ro & giảm thiểu

| Rủi ro | Mức | Giảm thiểu |
|---|---|---|
| Audio dataset bản quyền khó lấy | Cao | Tận dụng pseudo-label trên FMA/DALI/MAESTRO (đúng method paper) |
| AMD GPU local khó train (ROCm) | TB | Ưu tiên Kaggle/Colab; local chỉ inference/dev |
| Quantization giảm accuracy | TB | So distill vs PTQ vs QAT; giữ ngưỡng ~99% |
| Ableton Link tích hợp Flutter | TB | Platform channel; fallback WebRTC clock sync |
| Scope lớn | Cao | 2 track song song, mỗi phase có tiêu chí done |

---

## 10. Deliverable

1. `research_proposal.md` (file này) — đề cương chi tiết.
2. `ROADMAP_LEARNING.md` — lộ trình học theo phase.
3. `scripts/download_datasets.py` — tải dataset tự động + hướng dẫn phần tự tải.
4. `docs/superpowers/specs/2026-06-29-chordmind-design.md` — thiết kế kỹ thuật.
