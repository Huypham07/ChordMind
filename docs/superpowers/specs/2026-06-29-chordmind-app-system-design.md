# ChordMind — App System Design (App-first, models stubbed)

> Ngày: 2026-06-29
> Trạng thái: Draft để duyệt
> Phạm vi: **Track App đầy đủ** (mobile + server + sync + versioning). Mọi phần
> model là **stub slot** trả JSON canned — nối end-to-end, chỉ giả phần ruột model.
> Bổ sung cho `2026-06-29-chordmind-design.md` (thiết kế tổng thể).

## Quyết định đã chốt
- Client: **Flutter mobile-first** (bản web Flutter để sau).
- Backend: **server đầy đủ, model stub** — toàn bộ vertical nối thật, chỉ ruột model giả.
- Audio input: **YouTube link** (giống ChordMiniApp).
- Theme: **bản sắc ChordMind mới** (palette riêng, light + dark), giữ layout đã được kiểm chứng.
- DB: **Postgres** (Docker cho local dev).
- UI tham chiếu: `reference/ChordMiniApp/` (Next.js) — port pattern sang Flutter, layout mobile-first.

---

## 1. Scope & phasing

Một thiết kế cho **toàn bộ app system**, build theo 4 phase. Mọi thứ liên quan model
là **stub slot** trả fixture JSON.

| Phase | Giao gì | Model |
|---|---|---|
| **A0** Core vertical | Flutter app + design system (theme) + FastAPI skeleton + Postgres schema. YouTube paste → server trả `AnalysisResult` **canned** → chord grid đồng bộ, guitar/piano diagram, lyrics, player. | stub `ml_worker` |
| **A1** ml_interface | Hợp đồng `ModelSlot` (beat/chord/key/segment/melody) + job queue + cache. Mỗi slot = placeholder trả fixture. | stub slots |
| **A2** Band sync (H3) | WebRTC signaling server + P2P clock-sync UI + Ableton Link placeholder. | — |
| **A3** Versioning | Song version, sửa hợp âm, upvote/downvote, default version ("Wikipedia hợp âm"). | — |
| *(future)* | Tab re-harmonization on-device tồn tại dạng **placeholder** từ A0; TFLite thật cắm sau P4. | placeholder |

**A0 là milestone cho app chạy được + demo được.** Sync/versioning thiết kế ngay nhưng build sau.

---

## 2. Data model — hợp đồng trung tâm

Mirror `AnalysisResult` của ChordMiniApp làm JSON contract đông cứng giữa server và app
(đổi model không bao giờ phải sửa app):

```
AnalysisResult {
  songId,
  source:  { youtubeId, title, duration, bpm, timeSignature },
  key,                                    // "C major" (+ romanNumerals? optional)
  beats[]:      { time, beatNum },
  downbeats[]:  time,
  chords[]:     { chord, start, end, confidence },
  synchronizedChords[]: { chord, beatIndex },   // ô lưới grid
  segments[]:   { label, start, end },          // intro/verse/chorus
  melody?:      { ... }                         // experimental, optional
}
```

`ml_worker` stub trả instance viết tay cho ~3 bài seed, và một response canned chung cho
URL bất kỳ. **Đây là single source of truth — UI, sync, versioning đều đọc nó.**

Voicing hợp âm (guitar/piano "thế bấm") theo shape của reference: `{ frets[], fingers[], barres[], baseFret }`
(từ `reference/ChordMiniApp/src/utils/guitarVoicing.ts` + `types/react-chords.d.ts`).

---

## 3. Mobile app modules (Flutter)

Pattern UI lấy từ ChordMiniApp, vẽ lại theme mới, **layout mobile-first** (stack dọc,
control ở đáy, tab vuốt ngang — không dùng side-panel kiểu web).

```
app/mobile/lib/
  core/        theme (design system, light+dark), router, api client, models (AnalysisResult)
  features/
    home/        YouTube search/paste, recent songs
    player/      YouTube player + transport (play/loop/tempo/capo/pitch placeholder)
    chord_grid/  chord grid đồng bộ + beat highlighter + key/roman toggle    ← trọng tâm
    diagrams/    guitar chord diagram + piano keyboard ("thế bấm")            ← trọng tâm
    lyrics/      lyrics row đồng bộ với grid
    reharm/      re-harmonization on-device — TAB PLACEHOLDER (UI only)
    band/        join/host session, sync status (A2)
    versions/    version list, edit, vote (A3)
    settings/    theme toggle, instrument prefs
```

- Chord display + guitar/piano voicing nằm ở `chord_grid` + `diagrams`.
- YouTube playback: package `youtube_player_iframe`.
- State: Riverpod (đơn giản, không boilerplate thừa).

### Mobile layout chuẩn
- Player ở trên (collapsible), chord grid cuộn dọc bên dưới, control bar cố định ở đáy.
- Diagrams/lyrics là tab vuốt hoặc bottom sheet, không chiếm chỗ cố định.
- Grid responsive theo số ô/hàng vừa bề ngang điện thoại; tap ô → mở diagram thế bấm.

---

## 4. Server modules

```
server/
  api/            FastAPI: songs, versions, votes, auth (anonymous)   [REST]
  signaling/      WebSocket WebRTC signaling (A2)
  ml_worker/      job queue; submit → chạy slots → cache AnalysisResult
  ml_interface/   ModelSlot ABC: beat/chord/key/segment/melody
                  → A0: StubSlot trả fixture. Model thật cắm sau, không sửa app.
  db/             Postgres (Docker dev): songs, versions, votes, users
```

- YouTube: server lấy metadata (và audio cho pipeline stub); app phát qua iframe player.
- Pipeline nặng chạy 1 lần/bài rồi cache — đúng spec gốc, chỉ là slot đang stub.

ponytail:
- STUN-only lúc đầu; chỉ thêm TURN nếu NAT traversal thật sự fail khi test.
- Job queue: dùng `asyncio` task + bảng `jobs` trong Postgres làm hàng đợi; chỉ thêm
  Celery/Redis nếu throughput thật sự cần — `# ponytail: in-process queue, swap to broker if needed`.
- Auth anonymous: device-id token, chưa cần OAuth.

---

## 5. Theme / design system

Bản sắc ChordMind mới, định nghĩa một lần ở `core/theme`:
- Palette mới, light + dark, semantic tokens (surface, chord-active, beat-marker, segment colors…).
- Typography scale, spacing, widget tái dùng cho chord-cell + diagram.
- Sẽ chốt 1 trong các palette cụ thể ở bước lập plan implementation.

---

## 6. Placeholder / để-sau rõ ràng

| Hạng mục | Trạng thái A0 | Cắm thật khi |
|---|---|---|
| ModelSlot beat/chord/key/segment/melody | StubSlot trả fixture | sau P1/P4 (track Model) |
| Edge re-harmonization | Tab UI "coming soon" | sau P3/P4 |
| Band sync (WebRTC/Ableton Link) | Thiết kế xong, build ở A2 | A2 |
| Versioning/upvote | Thiết kế xong, build ở A3 | A3 |

---

## 7. Tiêu chí "done" cho A0

App chạy: paste URL YouTube → server trả `AnalysisResult` canned → app hiển thị chord grid
đồng bộ với player, mở được guitar/piano diagram khi tap ô hợp âm, có lyrics row, toggle
được light/dark theme. Server + Postgres chạy qua Docker. Re-harm/band/versions là tab
placeholder hoặc chưa hiện.
