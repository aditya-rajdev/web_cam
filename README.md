# PhoneCam - Free Phone-to-Webcam Application for Android + Windows

**PhoneCam** is a high-performance, 100% free, privacy-focused open-source solution that converts an Android smartphone into a real, system-wide webcam for Windows 10 and Windows 11.

---

## Key Features

- **DirectShow System Virtual Camera Integration**: Exposes the live Android camera feed as a selectable camera device named `PhoneCam` in **OBS Studio**, **Google Meet (Chrome / Edge)**, **Zoom**, **Microsoft Teams**, and **Discord**.
- **Dual Transport Modes**:
  - **Wi-Fi Mode**: Stream video wirelessly over local Wi-Fi with secure 6-digit PIN and QR code pairing.
  - **USB Mode (ADB)**: Low-latency USB streaming over local TCP tunnel (`adb forward tcp:8080 tcp:8080`).
- **Full Camera Controls**: Front/Back camera toggle, multi-lens selection, 1080p / 720p / 480p resolution selection, 24 / 30 / 60 FPS options, and horizontal mirror preview.
- **Hardware Acceleration**: Android `Camera2` / `CameraX` native pipeline with sub-5ms YUV-to-JPEG hardware compression.
- **Android Foreground Service**: Streaming remains active when switching apps or locking phone screen.
- **Zero Cloud Relay**: Direct local network/USB peer-to-peer transport without cloud servers, registration, accounts, or watermarks.

---

## System Requirements

- **Android Smartphone**: Android 7.0 (API 24) or higher.
- **Windows PC**: Windows 10 or Windows 11 (64-bit).
- **Development Tools (for building from source)**:
  - Flutter SDK `^3.13.1`
  - Visual Studio Build Tools 2022/2026 with C++ Workload
  - Android SDK (API 34+) with JDK 17

---

## Project Architecture & Directory Structure

```
phonecam/
├── android/                   # Native Android Kotlin project & Foreground Service
│   └── app/src/main/kotlin/   # YUV hardware compressor & MainActivity MethodChannel
├── windows/                   # Native Windows C++ Runner & DirectShow Filter
│   └── runner/native/         # Win32 DirectShow Virtual Camera DLL (PhoneCamFilter.dll)
├── lib/
│   ├── core/protocol/         # Shared binary frame protocol & handshake models
│   ├── features/
│   │   ├── camera/            # Android Camera2/X service & lens controller
│   │   ├── connection/        # Windows ADB manager for USB tunneling
│   │   ├── streaming/         # Android server & Windows stream receiver
│   │   ├── ui/                # Adaptive Material 3 UI for Android & Windows
│   │   └── virtual_camera/    # Native C++ Win32 FFI bindings
│   └── main.dart
├── test/                      # Protocol & Flutter unit tests
├── scripts/                   # System Virtual Camera Registration script
└── pubspec.yaml
```

---

## Building and Running

### 1. Run Tests & Static Analysis
```bash
flutter analyze
flutter test
```

### 2. Build Windows Application & Virtual Camera DLL
```bash
flutter build windows
```
Executable output: `build/windows/x64/runner/Release/PhoneCam.exe`
Virtual Camera Filter: `build/windows/x64/runner/Release/PhoneCamFilter.dll`

### 3. Build Android APK
```bash
flutter build apk --debug
```

---

## Registering the System Virtual Camera

To make `PhoneCam` visible inside video-conferencing apps (OBS, Zoom, Meet, Teams):
1. Run `PhoneCam.exe` on Windows and click **Install / Register Virtual Cam**.
2. Or run `scripts/register_virtual_cam.bat` as **Administrator**.
3. Launch OBS, Zoom, or Google Meet and select `PhoneCam` as your video input device!

---

## USB Mode Setup (ADB)

1. Connect phone to PC using a USB cable.
2. Enable **USB Debugging** in Android *Developer Options*.
3. In PhoneCam PC app, select **USB Mode** and click **Setup USB Tunnel**.
4. Tap **Start Camera Stream** on phone and connect to `127.0.0.1`.

---

## Dependency & License Inventory

- **Flutter SDK**: BSD 3-Clause License
- **Camera Plugin (`camera`)**: BSD 3-Clause License
- **Permission Handler (`permission_handler`)**: MIT License
- **QR Flutter (`qr_flutter`)**: MIT License
- **Network Info Plus (`network_info_plus`)**: BSD 3-Clause License
- **WebSocket Channel (`web_socket_channel`)**: BSD 3-Clause License
- **FFI & Win32 (`ffi`, `win32`)**: BSD 3-Clause License

---

## Privacy Statement

PhoneCam operates 100% locally on your home network and USB cable.
- No video frames or diagnostic metrics are transmitted to any external server.
- No personal user accounts or sign-ins are required.
- Pairing tokens are generated randomly per session.
