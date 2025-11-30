# Minimal OMI App

Minimal Flutter Android app to connect to OMI device and stream audio to a custom backend.

## Features

- Bluetooth scan for OMI devices
- Connect/disconnect to OMI device
- Display device info (name, codec, firmware, battery)
- Stream audio to custom WebSocket backend
- Real-time status indicators

## Setup

```bash
cd minimal-app
flutter pub get
```

## Run

```bash
flutter run
```

## Configuration

1. Start the minimal-backend server
2. In the app, enter the WebSocket URL:
   - For Android emulator: `ws://10.0.2.2:8000`
   - For physical device: `ws://YOUR_COMPUTER_IP:8000`

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/
│   ├── ble_constants.dart    # BLE UUIDs for OMI
│   └── omi_device.dart       # Device model
├── pages/
│   └── home_page.dart        # Main UI
└── services/
    ├── ble_service.dart      # Bluetooth operations
    ├── websocket_service.dart # WebSocket client
    └── audio_streamer.dart   # BLE -> WebSocket bridge
```

## Permissions

The app requires:
- Bluetooth
- Bluetooth Scan
- Bluetooth Connect
- Location (for BLE on Android)

## Usage

1. Tap "Scan" to find OMI devices
2. Tap "Connect" on your device
3. Configure the backend URL
4. Tap "Start Streaming" to begin audio capture
5. Check the backend for saved WAV files

