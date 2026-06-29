# ChordMind app (Flutter)

Ứng dụng mobile-first (có bản web để test/xem). Nhập link YouTube → xem hợp âm đồng bộ theo
nhạc + thế bấm guitar/piano; giao diện sáng/tối.

> Phân tích AI chạy trên mobile; **bản web không phân tích**, chỉ xem bài đã phân tích.

## Yêu cầu
- Flutter 3.x. API server chạy tại `http://localhost:8000` (xem `../server/README.md`).

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
