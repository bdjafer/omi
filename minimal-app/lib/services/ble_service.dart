import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:collection/collection.dart';
import '../models/ble_constants.dart';
import '../models/omi_device.dart';

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  final _devicesController = StreamController<List<OmiDevice>>.broadcast();
  Stream<List<OmiDevice>> get devicesStream => _devicesController.stream;
  final List<OmiDevice> _discoveredDevices = [];
  List<OmiDevice> get discoveredDevices => _discoveredDevices;
  StreamSubscription? _scanSubscription;
  OmiDevice? _connectedDevice;
  OmiDevice? get connectedDevice => _connectedDevice;
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  DeviceConnectionState get connectionState => _connectionState;
  final _connectionStateController = StreamController<DeviceConnectionState>.broadcast();
  Stream<DeviceConnectionState> get connectionStateStream => _connectionStateController.stream;
  StreamSubscription? _deviceConnectionSubscription;
  List<BluetoothService> _services = [];
  StreamSubscription? _audioSubscription;
  final _audioDataController = StreamController<List<int>>.broadcast();
  Stream<List<int>> get audioDataStream => _audioDataController.stream;
  final _batteryController = StreamController<int>.broadcast();
  Stream<int> get batteryStream => _batteryController.stream;
  StreamSubscription? _batterySubscription;

  Future<bool> isBluetoothOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  Future<void> startScan({int timeout = 5}) async {
    if (!await isBluetoothOn()) {
      print('Bluetooth is not on');
      return;
    }
    _discoveredDevices.clear();
    _devicesController.add(_discoveredDevices);
    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (OmiDevice.isOmiDevice(result)) {
          final existing = _discoveredDevices.firstWhereOrNull((d) => d.id == result.device.remoteId.str);
          if (existing == null) {
            _discoveredDevices.add(OmiDevice.fromScanResult(result));
            _devicesController.add(List.from(_discoveredDevices));
          }
        }
      }
    });
    await FlutterBluePlus.startScan(timeout: Duration(seconds: timeout));
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<bool> connect(OmiDevice device) async {
    try {
      _updateConnectionState(DeviceConnectionState.connecting);
      _deviceConnectionSubscription?.cancel();
      _deviceConnectionSubscription = device.bleDevice.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });
      await device.bleDevice.connect();
      await device.bleDevice.connectionState.where((s) => s == BluetoothConnectionState.connected).first;
      if (Platform.isAndroid) {
        await device.bleDevice.requestMtu(512);
      }
      _services = await device.bleDevice.discoverServices();
      _connectedDevice = device;
      await _readDeviceInfo();
      _updateConnectionState(DeviceConnectionState.connected);
      _startBatteryListener();
      return true;
    } catch (e) {
      print('Connection error: $e');
      _updateConnectionState(DeviceConnectionState.disconnected);
      return false;
    }
  }

  Future<void> disconnect() async {
    _audioSubscription?.cancel();
    _audioSubscription = null;
    _batterySubscription?.cancel();
    _batterySubscription = null;
    _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = null;
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.bleDevice.disconnect();
      } catch (e) {
        print('Disconnect error: $e');
      }
    }
    _connectedDevice = null;
    _services = [];
    _updateConnectionState(DeviceConnectionState.disconnected);
  }

  void _handleDisconnection() {
    _audioSubscription?.cancel();
    _audioSubscription = null;
    _batterySubscription?.cancel();
    _batterySubscription = null;
    _connectedDevice = null;
    _services = [];
    _updateConnectionState(DeviceConnectionState.disconnected);
  }

  void _updateConnectionState(DeviceConnectionState state) {
    _connectionState = state;
    _connectionStateController.add(state);
  }

  Future<void> _readDeviceInfo() async {
    if (_connectedDevice == null) return;
    final codecData = await _readCharacteristic(omiServiceUuid, audioCodecCharacteristicUuid);
    if (codecData.isNotEmpty) {
      _connectedDevice!.codec = BleAudioCodec.fromId(codecData[0]);
    }
    final batteryData = await _readCharacteristic(batteryServiceUuid, batteryLevelCharacteristicUuid);
    if (batteryData.isNotEmpty) {
      _connectedDevice!.batteryLevel = batteryData[0];
      _batteryController.add(batteryData[0]);
    }
    final firmwareData = await _readCharacteristic(deviceInformationServiceUuid, firmwareRevisionCharacteristicUuid);
    if (firmwareData.isNotEmpty) {
      _connectedDevice!.firmwareVersion = String.fromCharCodes(firmwareData);
    }
  }

  Future<List<int>> _readCharacteristic(String serviceUuid, String charUuid) async {
    try {
      final service = _services.firstWhereOrNull(
        (s) => s.uuid.str128.toLowerCase() == serviceUuid.toLowerCase(),
      );
      if (service == null) return [];
      final char = service.characteristics.firstWhereOrNull(
        (c) => c.uuid.str128.toLowerCase() == charUuid.toLowerCase(),
      );
      if (char == null) return [];
      return await char.read();
    } catch (e) {
      print('Read characteristic error: $e');
      return [];
    }
  }

  void _startBatteryListener() async {
    try {
      final service = _services.firstWhereOrNull(
        (s) => s.uuid.str128.toLowerCase() == batteryServiceUuid.toLowerCase(),
      );
      if (service == null) return;
      final char = service.characteristics.firstWhereOrNull(
        (c) => c.uuid.str128.toLowerCase() == batteryLevelCharacteristicUuid.toLowerCase(),
      );
      if (char == null) return;
      await char.setNotifyValue(true);
      _batterySubscription = char.lastValueStream.listen((value) {
        if (value.isNotEmpty) {
          _connectedDevice?.batteryLevel = value[0];
          _batteryController.add(value[0]);
        }
      });
    } catch (e) {
      print('Battery listener error: $e');
    }
  }

  Future<void> startAudioStream() async {
    if (_connectedDevice == null || _connectionState != DeviceConnectionState.connected) return;
    try {
      final service = _services.firstWhereOrNull(
        (s) => s.uuid.str128.toLowerCase() == omiServiceUuid.toLowerCase(),
      );
      if (service == null) {
        print('OMI service not found');
        return;
      }
      final char = service.characteristics.firstWhereOrNull(
        (c) => c.uuid.str128.toLowerCase() == audioDataStreamCharacteristicUuid.toLowerCase(),
      );
      if (char == null) {
        print('Audio characteristic not found');
        return;
      }
      await char.setNotifyValue(true);
      _audioSubscription = char.lastValueStream.listen((value) {
        if (value.isNotEmpty) {
          _audioDataController.add(value);
        }
      });
      _updateConnectionState(DeviceConnectionState.streaming);
      print('Audio stream started');
    } catch (e) {
      print('Start audio stream error: $e');
    }
  }

  Future<void> stopAudioStream() async {
    _audioSubscription?.cancel();
    _audioSubscription = null;
    if (_connectionState == DeviceConnectionState.streaming) {
      _updateConnectionState(DeviceConnectionState.connected);
    }
    print('Audio stream stopped');
  }

  BleAudioCodec? get currentCodec => _connectedDevice?.codec;

  void dispose() {
    _scanSubscription?.cancel();
    _audioSubscription?.cancel();
    _batterySubscription?.cancel();
    _deviceConnectionSubscription?.cancel();
    _devicesController.close();
    _connectionStateController.close();
    _audioDataController.close();
    _batteryController.close();
  }
}

