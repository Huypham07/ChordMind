# ChordMind app (Flutter)

Ứng dụng mobile-first (có bản web để test/xem). Nhập link YouTube → xem hợp âm đồng bộ theo
nhạc + thế bấm guitar/piano; giao diện sáng/tối.

> Phân tích AI chạy trên mobile; **bản web không phân tích**, chỉ xem bài đã phân tích.

## Tính năng
- Dán link YouTube → phát video kèm lưới hợp âm chạy theo nhịp (con trỏ beat).
- Bấm hợp âm → xem thế bấm guitar + piano.
- **Transpose** (đổi tông −12…+12) áp trực tiếp lên lưới, current-chord và thế bấm.
- **Local-first**: gọi server trước; server tắt/không có → đọc bản lưu trên máy; chưa có →
  nút "Sinh hợp âm" tạo mẫu và lưu lại (chơi được offline). Sync với server để sau.
- Giao diện sáng/tối.

## Yêu cầu
- Flutter 3.x. API server (`http://localhost:8000`, xem `../server/README.md`) là **tuỳ chọn** —
  không có thì app tự dùng dữ liệu lưu trên máy.

## Cài đặt & chạy
```bash
flutter pub get
flutter run -d chrome          # web (test); hoặc -d <device> cho mobile/emulator
```

## Test
```bash
flutter test
```

## Build web
```bash
flutter build web              # ra build/web (image web trong docker-compose.app.yml dùng bản này)
```
