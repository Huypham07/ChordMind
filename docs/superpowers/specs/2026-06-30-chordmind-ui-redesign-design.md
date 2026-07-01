# ChordMind — UI Redesign Design Spec

> Ngày: 2026-06-30 · Trạng thái: Draft để duyệt
> Phạm vi: Thiết kế lại toàn bộ giao diện app (Flutter) thành **product chỉn chu**,
> phong cách **vibrant kiểu Spotify**, **light + dark đều đẹp ngang nhau**, và
> **responsive: web ra layout web, mobile ra layout mobile**.
> Không đổi logic (sync, repository, models, API, routing) — chỉ theme + layout + widget.

## 0. Mục tiêu & nguyên tắc
- Nhìn như một sản phẩm thật, không phải skeleton: spacing rộng, bo góc, bóng mềm, gradient nhấn, có trạng thái (loading/empty/hover/pressed).
- **Adaptive theo nền tảng**, không chỉ co giãn:
  - **Mobile (compact):** stack dọc, điều hướng dưới, diagram dạng bottom sheet, thao tác chạm.
  - **Web/desktop (expanded):** NavigationRail/sidebar, bố cục đa cột, panel cố định bên phải, hover state, giới hạn bề rộng nội dung.
- Light & dark đều được tinh chỉnh; theo system, có toggle.
- Màu chốt tạm ở §2 — **tinh chỉnh chính xác qua screenshot** trong lúc dựng.

## 1. Giữ nguyên (không động vào)
`grid_sync.activeChordIndex`, `SongRepository`/`api`, `models`, `router`, các endpoint server. Chỉ thay phần trình bày.

## 2. Design tokens (chốt tạm)

### Gradient thương hiệu
`brandGradient` = tuyến tính 135°, `#8B5CF6` (violet) → `#EC4899` (pink). Dùng cho: nút primary, hero, ô hợp âm đang vang (active), thanh "đang chơi".

### Màu — Dark
| Token | Hex |
|---|---|
| background | `#0E0D12` |
| surface | `#1A1820` |
| surfaceAlt | `#232030` |
| border | `#2A2733` |
| text | `#ECEAF2` |
| textMuted | `#9D98AD` |
| primary | `#8B5CF6` |
| secondary | `#EC4899` |

### Màu — Light
| Token | Hex |
|---|---|
| background | `#FAFAFB` |
| surface | `#FFFFFF` |
| surfaceAlt | `#F2F1F5` |
| border | `#E6E4EC` |
| text | `#1A1820` |
| textMuted | `#6B6878` |
| primary | `#8B5CF6` |
| secondary | `#EC4899` |

### Semantic
- `chordActive`: nền = brandGradient + glow (shadow violet/pink ~20% alpha, blur 16).
- `chordIdle`: surfaceAlt.
- `beatMarker`: primary.
- `segment`: verse = violet 14% tint, chorus = pink 14% tint, intro/outro/bridge = muted tint.
- `danger`: `#F43F5E`.

### Hình khối
- Radius: sm 8 · md 12 · lg 16 · xl 20 · pill 999.
- Shadow mềm: light `0 4 16 rgba(20,16,32,.08)`; dark `0 4 16 rgba(0,0,0,.40)`.
- Spacing scale: 4 · 8 · 12 · 16 · 24 · 32 · 48.

### Typography (thêm `google_fonts`)
- Display/heading: **Sora** (geometric, hiện đại). Body/label: **Inter**.
- Thang: display 28 · h1 22 · h2 18 · title 16 · body 15 · label 13 · caption 12.

## 3. Component library (tái dùng, định nghĩa 1 chỗ)
`core/theme/` (tokens + `ChordMindColors` extension + `AppGradients` + text theme) và `core/widgets/`:
- `GradientButton` (primary CTA), `AppCard` (surface + radius lg + shadow), `InfoChip` (key/BPM/capo), `SectionHeader` (Verse/Chorus + đường kẻ), `PillTabs` (segmented control thay TabBar), `SearchPill` (ô dán link), `CurrentChordBar` (hợp âm hiện tại to + kế tiếp), `ChordCell` (idle/active có glow), `AppScaffold` (adaptive shell: NavigationRail trên web, BottomNav/AppBar trên mobile), `EmptyState`, `LoadingShimmer`.

## 4. Responsive — breakpoints & shell
Dùng `LayoutBuilder`/`MediaQuery` với mốc:
- **compact** `< 600`: mobile. Điều hướng: bottom nav (Home/Player/Settings) hoặc AppBar; nội dung 1 cột; diagram = bottom sheet.
- **medium** `600–1024`: tablet/web hẹp — nav rail thu gọn, lưới hợp âm nhiều cột hơn.
- **expanded** `≥ 1024`: web/desktop. `NavigationRail` trái; nội dung giới hạn bề rộng (~1100px), có panel phải cố định cho diagram/lyrics; có hover state.

`AppScaffold` chọn shell theo breakpoint để cùng một màn hình "ra web" hoặc "ra mobile".

## 5. Bố cục từng màn hình

### Home
- **Mobile:** AppBar gọn → hero gradient (logo + tagline) → `SearchPill` dán link YouTube → `GradientButton` Analyze → "Gần đây" dạng list card (thumbnail gradient + title + chip key/bpm).
- **Web:** NavigationRail trái (Home/Library/Settings) → khu giữa: hero banner ngang + SearchPill rộng → "Gần đây" dạng **lưới card responsive** (2–4 cột theo bề rộng), card có hover nhấc nhẹ.

### Player (màn hình chính)
- **Chung:** video YouTube trong `AppCard` bo tròn; hàng title + `InfoChip` key/BPM/(capo); `CurrentChordBar` (hợp âm đang vang to + "kế tiếp"); lưới hợp âm **nhóm theo ô nhịp/measure** với `SectionHeader` theo segment; ô active tô gradient + glow; tab `PillTabs` (Chords/Lyrics/Re-harm/Band/Versions).
- **Mobile:** xếp dọc, player có thể collapse khi cuộn; tab vuốt ngang; tap ô hợp âm → **bottom sheet** diagram.
- **Web:** 2 cột — trái: player + info + lưới hợp âm (rộng, nhiều cột); phải: **panel cố định** hiện diagram (guitar+piano) của hợp âm đang chọn + lyrics; không dùng bottom sheet.

### Diagrams (chỉn chu)
- **Guitar:** khung phím có **nut**, nhãn fret, ký hiệu **X (muted) / O (open)** trên đầu dây, chấm ngón bo tròn, vẽ **barre**, tên hợp âm.
- **Piano:** đủ **phím trắng + đen** một quãng tám, nốt thuộc hợp âm **glow** theo accent.
- Vị trí: mobile = bottom sheet; web = panel phải.

## 6. Web ≠ Mobile (làm rõ yêu cầu)
- Web: có sidebar/nav rail, đa cột, panel phải, hover, con trỏ, giới hạn bề rộng — cảm giác **app web thật**.
- Mobile: bottom nav, full-width card, bottom sheet, vùng chạm ≥ 44px — cảm giác **app mobile thật**.
- Cùng tính năng, khác cách trình bày theo `AppScaffold` + breakpoint.

## 7. Light + dark
Cả hai bảng token ở §2 đều phải nhìn đẹp; kiểm tra tương phản chữ ≥ WCAG AA. Toggle theme ở Settings + theo system mặc định.

## 8. Phạm vi & cách validate
- Một pass UI (độc lập model). Demo trên **web** ngay, đồng thời build mobile để kiểm bố cục mobile.
- **Validate bằng screenshot**: dựng từng phần → chụp web (compact + expanded) → tinh chỉnh màu/spacing tới khi "ra product". Màu §2 là điểm khởi đầu, được phép chỉnh.
- Không thêm dependency ngoài `google_fonts` (typography). Các hiệu ứng (gradient/shadow/blur) dùng Flutter sẵn có.

## 9. Tiêu chí "done"
- Home/Player/Diagrams nhìn như product: gradient brand, card, typography Sora/Inter, trạng thái đầy đủ.
- Trên web (≥1024) hiện nav rail + 2 cột + panel phải + hover; trên mobile (<600) hiện stack + bottom sheet + điều hướng dưới.
- Light & dark đều chỉn chu. Toàn bộ test cũ vẫn pass; `flutter build web` ok; chụp được screenshot light+dark ở cả 2 breakpoint.
