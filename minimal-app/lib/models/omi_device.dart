import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_constants.dart';

class OmiDevice {
  final String id;
  final String name;
  final int rssi;
  final BluetoothDevice bleDevice;
  int batteryLevel;
  BleAudioCodec codec;
  String? firmwareVersion;

  OmiDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.bleDevice,
    this.batteryLevel = -1,
    this.codec = BleAudioCodec.pcm8,
    this.firmwareVersion,
  });

  factory OmiDevice.fromScanResult(ScanResult result) {
    return OmiDevice(
      id: result.device.remoteId.str,
      name: result.device.platformName.isNotEmpty ? result.device.platformName : 'OMI Device',
      rssi: result.rssi,
      bleDevice: result.device,
    );
  }

  static bool isOmiDevice(ScanResult result) {
    return result.advertisementData.serviceUuids.any(
      (uuid) => uuid.toString().toLowerCase() == omiServiceUuid.toLowerCase(),
    );
  }
}

enum DeviceConnectionState {
  disconnected,
  connecting,
  connected,
  streaming,
}

