# ROADMAP HỌC TẬP & TRIỂN KHAI — ChordMind

> Lộ trình học theo phase cho 2 track song song. Mỗi phase: **mục tiêu → kiến thức cần học → tài nguyên (paper/khóa/repo) → việc làm → tiêu chí "done"**.
> Xem thiết kế kỹ thuật: `docs/superpowers/specs/2026-06-29-chordmind-design.md`.

Ký hiệu: 🎓 kiến thức · 📚 tài nguyên · 🔧 việc làm · ✅ done khi.

> **Đọc PHẦN F (Nền tảng) trước.** Đây là bản đồ khái niệm từ gốc → chuyên sâu.
> Mỗi mục: **định nghĩa ngắn → vai trò trong ChordMind → tài nguyên học**.
> Không cần học thuộc; học đến đâu hiểu "nó là gì, dùng ở đâu trong dự án" đến đó.

---

# PHẦN F — NỀN TẢNG KIẾN THỨC (học trước khi vào các phase)

## F1. Toán & Machine Learning cơ bản
Thứ tự: **tensor/vector/ma trận → hàm mất mát (loss) → gradient descent → backpropagation → overfitting/regularization → train/val/test split**.
- *Là gì:* Mạng nơ-ron học bằng cách điều chỉnh tham số để giảm "loss" (sai số) qua gradient descent; backprop là cách tính gradient. Overfitting = học vẹt tập train, kém trên dữ liệu mới.
- *Vai trò:* Mọi mô hình trong dự án (chord, beat, generative) đều train theo nguyên lý này. Hiểu loss/overfitting là điều kiện để đọc được kết quả paper.
- 📚 3Blue1Brown "Neural Networks" (YouTube, trực giác); Andrew Ng "Machine Learning Specialization" (Coursera); fast.ai "Practical Deep Learning".

## F2. Xử lý tín hiệu âm thanh (DSP cho âm nhạc)
Thứ tự: **waveform & sample rate → FFT/STFT → spectrogram → CQT → chroma**.
- *Là gì:* Âm thanh là sóng theo thời gian. STFT biến nó thành ảnh "tần số theo thời gian" (spectrogram). **CQT (Constant-Q Transform)** giống STFT nhưng chia tần số theo thang log — khớp với cách nốt nhạc cách nhau, nên rất hợp cho nhận diện hợp âm. **Chroma** gộp năng lượng về 12 pitch class (C, C#, ...).
- *Vai trò:* Paper dùng **CQT làm đầu vào** cho mô hình hợp âm (F=144 bins, 24 bins/octave, hop=2048, fs=22.05kHz). Đây là "ảnh" mà CNN/Transformer nhìn vào để đoán hợp âm. Nhánh H2 thay CQT bằng embedding MuQ.
- 📚 Valerio Velardo "Audio Signal Processing for ML" (YouTube series); librosa docs (mục CQT, chroma).

## F3. Lý thuyết âm nhạc tối thiểu
- *Là gì:* Hợp âm = nhiều nốt vang cùng lúc. **Triad** (3 nốt: major/minor/dim/aug), **seventh** (4 nốt), **inversion** (đảo), **slash chord** (C/E). "Vocabulary 170 lớp" trong paper = 170 loại hợp âm mô hình phân biệt được. Key (tông), beat (phách), downbeat (phách mạnh).
- *Vai trò:* Là "nhãn" (label) mà mô hình ACR dự đoán; là không gian đầu ra của mô hình sinh hợp âm (H1b).
- 📚 musictheory.net; Harte 2010 (chuẩn ký hiệu hợp âm dùng trong MIR).

## F4. Các khối mạng nơ-ron (đọc kỹ — đây là "CNN là gì"...)
Học lần lượt:
- **MLP / fully-connected:** mạng cơ bản nhất, mỗi nơ-ron nối hết lớp trước.
- **CNN (Convolutional Neural Network):** dùng "bộ lọc" (kernel) trượt trên ảnh/spectrogram để bắt **mẫu cục bộ** (local pattern) — vd hình dạng năng lượng của một hợp âm trên CQT. Mạnh ở phát hiện đặc trưng không gian/tần số. → Đây là phần "CNN" trong **chord-cnn-lstm**.
- **RNN / LSTM:** mạng xử lý **chuỗi tuần tự**, nhớ ngữ cảnh quá khứ. LSTM khắc phục việc RNN quên thông tin dài. → Phần "LSTM" trong chord-cnn-lstm dùng để mượt hóa hợp âm theo thời gian.
- **Attention & Transformer:** cơ chế cho mỗi vị trí "nhìn" mọi vị trí khác và tự quyết trọng số → bắt phụ thuộc **xa** rất tốt, chạy song song. Self-attention = nhìn trong cùng chuỗi; cross-attention = chuỗi này nhìn chuỗi kia.
- *Vai trò:* CNN bắt mẫu hợp âm trên CQT; LSTM/Transformer mô hình hóa tiến trình hợp âm theo thời gian. Hiểu 4 khối này là đủ để đọc mọi kiến trúc trong dự án.
- 📚 CNN: CS231n (Stanford) lecture đầu; LSTM: colah's blog "Understanding LSTM Networks"; Transformer: "The Illustrated Transformer" (Jay Alammar) + "Attention Is All You Need" (Vaswani 2017).

## F5. Các kiến trúc ACR cụ thể trong dự án
- **BTC (Bi-directional Transformer for Chord recognition, Park 2019):** xếp chồng nhiều lớp Transformer hai chiều (nhìn cả quá khứ & tương lai) trên đặc trưng CQT, + CRF để mượt chuỗi đầu ra. Kiến trúc **sâu**. → Là **teacher** sinh pseudo-label trong paper.
- **chord-cnn-lstm (ISMIR 2019, large-voca):** CNN trích đặc trưng + LSTM theo thời gian + phân rã cấu trúc hợp âm + HMM decode. Tác giả app đánh giá tổng thể tốt → **baseline ưu tiên** bước 3.
- **ChordNet / 2E1D (paper ChordMini):** thuần Transformer (không CNN), 2 encoder (tần số + thời gian) + cross-attention fusion, kiến trúc **rộng** (2.2M tham số), có Gaussian smoothing + sliding-window vote khi suy luận.
- *Vai trò:* Ba "ứng viên" cho bước nhận diện hợp âm; bạn đã có sẵn checkpoint cả ba.
- 📚 các paper tương ứng + đọc code trong `reference/BTC-ISMIR19`, `reference/chord-cnn-lstm-model`, `reference/ChordMini/src`.

## F6. Các phương pháp huấn luyện (trọng tâm paper)
- **Supervised learning:** học từ dữ liệu có nhãn (audio ↔ hợp âm).
- **Pseudo-labeling / semi-supervised:** dùng một mô hình đã train (teacher) để **tự gán nhãn** cho khối lớn audio **không nhãn**, rồi train mô hình mới (student) trên nhãn-giả đó. → Stage 1 của paper, tận dụng FMA/DALI/MAESTRO.
- **Knowledge Distillation (KD):** student học từ "soft label" (phân phối xác suất) của teacher thay vì chỉ nhãn cứng — giàu thông tin hơn. Trong paper KD đóng vai **regularizer** chống học theo nhãn nhiễu. Công thức: loss = α·KD + (1−α)·CE; α=0.3, nhiệt độ τ=3.0.
- **Continual learning & catastrophic forgetting:** học dữ liệu mới mà **quên** kiến thức cũ = "catastrophic forgetting". Continual learning = học thêm dữ liệu mới (Stage 2: nhãn thật) mà giữ được kiến thức Stage 1; paper dùng KD từ teacher làm "mỏ neo" để chống quên.
- *Vai trò:* Đây chính là đóng góp của paper tham chiếu (2-stage). Bạn cần hiểu để (a) tái lập baseline P1, (b) định vị đóng góp mới của mình so với nó.
- 📚 Hinton 2015 "Distilling the Knowledge in a Neural Network"; Lee 2013 (pseudo-label); "Noisy Student" (Xie 2020); "Learning without Forgetting" (Li & Hoiem); khảo sát continual learning (van de Ven 2019).

## F7. Foundation models & Self-Supervised Learning (cho nhánh H2)
- *Là gì:* **SSL** = học biểu diễn từ dữ liệu **không nhãn** bằng cách tự tạo bài toán phụ. **Foundation model** = mô hình lớn pretrain trên khối dữ liệu khổng lồ, dùng lại cho nhiều task. **MuQ** học biểu diễn nhạc bằng Mel-RVQ, cho embedding mạnh.
- *Vai trò:* H2 thay CQT thủ công bằng embedding MuQ làm đầu vào ACR, kỳ vọng cải thiện hợp âm hiếm.
- 📚 MuQ paper (arXiv:2501.01108); tổng quan SSL (Wav2Vec2/HuBERT để hiểu nguyên lý chung).

## F8. Sinh nhạc ký hiệu (Generative symbolic music — H1b)
- *Là gì:* Sinh chuỗi hợp âm/MIDI bằng mô hình sinh (Transformer decoder, VAE). Điều kiện hóa = ép đầu ra theo tone/style mong muốn.
- *Vai trò:* Bước 7 (biến tấu vòng hợp âm) và bước 8 (đệm) của dự án.
- 📚 MusicVAE (Magenta); "Anticipatory Music Transformer"; cơ bản về VAE và autoregressive generation.

## F9. Nén mô hình & Edge AI (H1a)
- *Là gì:* **Quantization** = giảm độ chính xác số (FP32→INT8) cho mô hình nhỏ & nhanh (PTQ = sau khi train; QAT = train có mô phỏng lượng hóa). **Pruning** = cắt tham số thừa. **Distillation** (đã học F6) cũng dùng để thu nhỏ. **ONNX/TFLite** = định dạng để chạy on-device.
- *Vai trò:* Đóng góp H1a — đưa mô hình ACR/generative chạy real-time trên điện thoại.
- 📚 TensorFlow Lite docs (quantization); PyTorch quantization tutorial; ONNX Runtime Mobile.

## F10. Nền tảng App & Hệ thống real-time (H3)
- *Là gì:* **Flutter** (UI đa nền tảng), **FastAPI** (backend REST async), **WebRTC** (P2P, DataChannel, signaling), **Ableton Link** (đồng bộ BPM giữa thiết bị), **latency compensation** (bù trễ).
- *Vai trò:* Track App + đồng bộ ban nhạc.
- 📚 Flutter docs; FastAPI docs; webrtc.org "Getting Started"; Ableton Link SDK (GitHub README).

### Thứ tự học đề xuất cho PHẦN F
F1 → F2 → F3 (nền chung) → F4 (khối mạng) → F5 (kiến trúc cụ thể) → F6 (phương pháp train, trọng tâm) → rồi rẽ nhánh theo việc đang làm: H2→F7, H1b→F8, H1a→F9, App→F10.

> Khi đã nắm F1–F6, bạn đủ base để bắt đầu **P0/P1** bên dưới. F7–F10 học khi tới phase tương ứng.

---

## TRACK MODEL (Kaggle/Colab notebooks)

### P0 — Nền tảng xử lý tín hiệu âm thanh & đánh giá MIR
🎓 Cần nắm:
- Biểu diễn audio: waveform, sample rate, STFT vs **CQT** (Constant-Q Transform — paper dùng F=144 bins, 24 bins/octave, hop=2048, fs=22.05kHz, Δt≈93ms).
- Chroma features, pitch class, lý thuyết hòa thanh cơ bản (triad, seventh, inversion, slash chord, vocabulary 170 lớp).
- Đánh giá ACR: `mir_eval` — Root/Thirds/Triads/Sevenths/Tetrads/Majmin/MIREX, WCSR, **ACQA** (nhạy hợp âm hiếm), Over/Under/Seg.

📚:
- librosa docs (CQT, chroma) — librosa.org.
- `mir_eval` docs + paper Raffel et al. 2014.
- Harte 2010 (chord notation), Humphrey & Bello (deep learning for ACR).
- Khóa: "Audio Signal Processing for ML" (Valerio Velardo, YouTube).

🔧: Viết notebook tải 1 file audio → CQT → hiển thị; chạy `mir_eval` trên 1 cặp nhãn dự đoán/ground-truth giả.
✅ Done khi: tự tính được CQT đúng tham số paper và đọc/giải thích được mọi metric trong bảng kết quả paper.

---

### P1 — Tái lập baseline ACR (3 mô hình)
🎓: Kiến trúc BTC (bi-directional transformer + self-attention), CRF decoding; chord-cnn-lstm (chord structure decomposition + HMM decode); ChordNet 2E1D (dual encoder freq+temporal + cross-attention, Gaussian smoothing, sliding window vote).

📚:
- Park et al. 2019 "A Bi-Directional Transformer for Musical Chord Recognition" + repo `reference/BTC-ISMIR19/`.
- ISMIR2019 "Large-Vocabulary Chord Transcription via Chord Structure Decomposition" + repo `reference/chord-cnn-lstm-model/`.
- Paper ChordMini (`reference/arXiv-2602.19778v3/DAFx26_tmpl.tex`) + repo `reference/ChordMini/`.

🔧:
- Load 3 checkpoint đã có (`reference/ChordMini/checkpoints/`, `reference/model_checkpoints/`).
- Chạy inference trên vài bài → xuất `.lab` → so sánh với nhãn → tái lập số trong bảng §1 spec.
- Lập bảng baseline của riêng mình (Root/.../MIREX + ACQA).
✅ Done khi: tái lập được (sai số nhỏ) số liệu paper cho ít nhất BTC teacher và 2E1D.

---

### P2 — Nhánh H2: MuQ backbone thay CQT
🎓: Self-supervised music representation, Mel-RVQ, cách trích hidden states từ MuQ; probing/fine-tune foundation model cho downstream.

📚:
- MuQ paper (arXiv:2501.01108) + repo `reference/MuQ/` (`pip install muq`, `MuQ.from_pretrained("OpenMuQ/MuQ-large-msd-iter")`).
- MARBLE benchmark.

🔧:
- Trích embedding MuQ cho tập labeled → thay đầu vào CQT của bộ chord head → train head/fine-tune.
- So sánh ACR (đặc biệt ACQA, 7ths/Tetrads) giữa CQT-baseline và MuQ-backbone.
✅ Done khi: có bảng so sánh CQT vs MuQ trên cùng test set, kết luận rõ ràng có/không cải thiện rare chords.

---

### P3 — Nhánh H1b: Generative re-harmonization & accompaniment (supervised)
🎓: Mô hình sinh chuỗi hợp âm (Transformer decoder / VAE), điều kiện hóa (tone, style, độ phức tạp); biểu diễn symbolic music (chord token, MIDI), voice-leading & hòa thanh chức năng.

📚:
- MusicVAE (Magenta), Anticipatory Music Transformer (Thickstun et al.).
- Hooktheory dataset, Chordonomicon, Lakh MIDI.
- Lý thuyết hòa thanh: reharmonization, substitution, modal interchange.

🔧:
- Re-harm: train trên Hooktheory/Chordonomicon, input vòng hợp âm gốc + điều kiện → output vòng mới.
- Accompaniment: baseline rule-based (arpeggio/comping từ chord+beat) → model MIDI trên Lakh.
- Metric nhạc lý + chuẩn bị giao thức user study.
✅ Done khi: sinh được vòng hợp âm đổi tone/style hợp lệ nhạc lý + 1 demo đệm MIDI nghe được.

---

### P4 — Nhánh H1a: Edge quantization & export
🎓: Distillation, pruning, quantization (PTQ vs QAT), ONNX, TFLite INT8, đo latency/size; chạy inference on-device.

📚:
- TensorFlow Lite / ONNX Runtime Mobile docs; PyTorch quantization docs.
- "Knowledge Distillation" Hinton 2015 (đã dùng trong paper).

🔧:
- Lấy model bước 3 (và 7) → distill xuống nhỏ hơn → PTQ → (nếu rớt nhiều) QAT → export ONNX + TFLite.
- Benchmark trên điện thoại thật: Δaccuracy, latency (ms), size (MB), RAM.
- Lập bảng đánh đổi accuracy ↔ latency ↔ size.
✅ Done khi: có model TFLite chạy real-time on-device giữ ≈99% accuracy gốc + bảng benchmark đầy đủ.

---

## TRACK APP (song song với Track Model)

### A0 — Khung dự án (Flutter + FastAPI + DB)
🎓: Flutter cơ bản (widget, state mgmt), FastAPI (REST, async), thiết kế schema DB (songs/versions/votes/users).
📚: Flutter docs, FastAPI docs, Firestore hoặc Postgres docs.
🔧: Scaffold `app/mobile` (Flutter) + `server/api` (FastAPI) + `db/` schema; CRUD bài hát + version cơ bản; màn hình player + chord grid tĩnh.
✅ Done khi: chạy được app rỗng hiển thị 1 bài hát mock với grid hợp âm, đọc/ghi version qua API.

### A1 — `ml_interface` + `ml_worker` (cắm model bước 1-6)
🎓: Thiết kế interface/abstraction, hợp đồng I/O JSON schema, hàng đợi tác vụ nền (job queue), caching.
📚: tham khảo `reference/ChordMiniApp/python_backend/` (cách họ ghép Beat-Transformer/chord/SongFormer/SheetSage).
🔧: Định nghĩa `ModelSlot` (beat/chord/key/segment/melody) với I/O cố định; `ml_worker` chạy pipeline khi upload bài mới → cache JSON; nối vào app.
✅ Done khi: upload 1 bài thật → server chạy beat+chord+segment → app hiển thị grid đồng bộ; chạy lại bài đó lấy từ cache.

### A2 — Đồng bộ real-time (H3)
🎓: WebRTC (DataChannel, signaling, ICE/STUN/TURN), Ableton Link (BPM sync, platform channel C++↔Flutter), latency compensation.
📚: webrtc.org, Ableton Link SDK (GitHub), tài liệu flutter_webrtc.
🔧: `server/signaling` (WebSocket) cho P2P; truyền JSON clock sync; tích hợp Ableton Link qua platform channel; fallback clock sync thuần.
✅ Done khi: 2 thiết bị cùng phách, đo được độ lệch (ms) và băng thông; demo ban nhạc 2-3 máy.

### A3 — Versioning cộng đồng ("Wikipedia hợp âm")
🎓: Mô hình version/branch, CRDT cơ bản, upvote/downvote, chọn Default Version, anonymous auth.
📚: tham khảo cấu trúc Firestore collections của ChordMiniApp (transcriptions/versions).
🔧: Tạo version từ chỉnh sửa người dùng; upvote/downvote; tự chọn bản chuẩn; chống spam cơ bản.
✅ Done khi: nhiều user sửa cùng 1 bài → nhiều version → cộng đồng vote → hiển thị Default.

---

## GHÉP 2 TRACK
Sau **P4** (model export) và **A1** (ml_interface): cắm ONNX/TFLite vào `ml_worker` (bước nặng) và `app/mobile/edge` (re-harmonization on-device). Không cần sửa logic app nhờ `ml_interface`.

---

## DATASET — hướng dẫn lấy

### Tải tự động (xem `scripts/download_datasets.py`)
| Dataset | Dùng cho | Nguồn |
|---|---|---|
| FMA (small/medium/large) | pseudo-label, beat | github.com/mdeff/fma, Zenodo |
| MAESTRO v3 | pseudo-label (piano) | magenta.tensorflow.org/datasets/maestro |
| MuQ weights | backbone H2 | HuggingFace `OpenMuQ` (auto khi `from_pretrained`) |
| Lakh MIDI (LMD) | accompaniment | colinraffel.com/projects/lmd |
| Hooktheory | re-harmonization | HuggingFace / hooktheory API |
| Chordonomicon | re-harmonization | HuggingFace |
| Ballroom / GTZAN / Hainsworth | eval beat | qua `mirdata` |
| Harmonix / SALAMI | eval segmentation | Zenodo / `mirdata` |

### Phải tự xin/tự tải (audio bản quyền — chỉ có nhãn)
| Dataset | Nhãn lấy ở đâu | Audio |
|---|---|---|
| Isophonics | isophonics.net/datasets | tự tìm audio gốc |
| McGill Billboard | ddmal.music.mcgill.ca/research/billboard | tự tìm audio |
| RWC-Pop | staff.aist.go.jp/m.goto/RWC-MDB (đăng ký) | mua/đăng ký license RWC |
| USPop2002 | github.com/tmc323/Chord-Annotations | tự tìm audio |
| DALI | github.com/gabolsgabs/DALI (metadata) | crawl theo link YouTube trong metadata |

> Đúng như BTC-ISMIR19 README ghi: các dataset chord chuẩn chỉ phát hành **nhãn**, audio phải tự thu thập do bản quyền. Đây là lý do paper dùng pseudo-label trên FMA/DALI/MAESTRO — ta đi theo cùng chiến lược để giảm phụ thuộc audio bản quyền.

---

## THỨ TỰ ĐỀ XUẤT
1. P0 → P1 (nắm nền + tái lập baseline) **song song** A0 → A1 (có app chạy được với model có sẵn).
2. P2 (MuQ) và A2 (sync) chạy song song.
3. P3 (generative) và A3 (versioning).
4. P4 (edge) → ghép cuối.

Không có ràng buộc thời gian; ưu tiên làm sâu, ghi lại số liệu/đánh giá ở mỗi bước để phục vụ paper/luận văn.
