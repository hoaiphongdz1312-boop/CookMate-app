# CookMate

Ứng dụng Android hướng dẫn nấu món Việt từng bước: điều khiển bằng giọng nói tiếng Việt ("Bếp ơi"), đăng nhập bằng khuôn mặt và cộng đồng chia sẻ công thức.

## Tải ứng dụng

| Thiết bị | File cài đặt |
|---|---|
| **Điện thoại Android** (hầu hết máy) | [⬇ app-arm64-v8a-release.apk](https://github.com/hoaiphongdz1312-boop/CookMate-app/releases/latest/download/app-arm64-v8a-release.apk) |
| Điện thoại Android đời cũ | [⬇ app-armeabi-v7a-release.apk](https://github.com/hoaiphongdz1312-boop/CookMate-app/releases/latest/download/app-armeabi-v7a-release.apk) |
| Máy ảo trên máy tính (BlueStacks, Android Emulator) | [⬇ app-x86_64-release.apk](https://github.com/hoaiphongdz1312-boop/CookMate-app/releases/latest/download/app-x86_64-release.apk) |

Tất cả phiên bản: [Releases](https://github.com/hoaiphongdz1312-boop/CookMate-app/releases)

**Cách cài:** tải file APK về điện thoại → mở file → cho phép "Cài ứng dụng không rõ nguồn gốc" nếu được hỏi. Nếu Play Protect cảnh báo, chọn "Vẫn cài đặt".

Yêu cầu: Android 8.0 trở lên, có kết nối Internet. Lần đầu bật giọng nói, ứng dụng cần vài giây để nạp mô hình tiếng Việt.

## Liên kết

- Server API (ASP.NET Core): [CookMate-server](https://github.com/hoaiphongdz1312-boop/CookMate-server)
- Tài liệu API (Swagger): https://cookmate2026-001-site1.dtempurl.com/swagger

## Công nghệ

Flutter, go_router, dio, Google ML Kit + MobileFaceNet (TensorFlow Lite) cho nhận diện khuôn mặt, Vosk cho nhận dạng giọng nói tiếng Việt offline, đăng nhập Google.

## Build từ mã nguồn

```bash
flutter pub get
flutter run --dart-define-from-file=env.json
```

`env.json` tạo từ `env.example.json` (điền Web client ID của Google). Bản release ký bằng khóa khai báo trong `android/key.properties` (xem `android/key.properties.example`); thiếu file này thì dùng khóa debug.
