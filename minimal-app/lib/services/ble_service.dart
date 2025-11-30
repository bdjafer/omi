import 'dart:async';
import 'dart:io';
import 'dart:math';
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
  String? _lastConnectedDeviceId;
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
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 15;
  bool _shouldReconnect = false;
  Timer? _connectionWatchdog;

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
    _lastConnectedDeviceId = device.id;
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    return await _connectToDevice(device);
  }

  Future<bool> _connectToDevice(OmiDevice device) async {
    try {
      _updateConnectionState(DeviceConnectionState.connecting);
      _deviceConnectionSubscription?.cancel();
      _deviceConnectionSubscription = device.bleDevice.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });
      await device.bleDevice.connect(autoConnect: false, timeout: const Duration(seconds: 15));
      await device.bleDevice.connectionState.where((s) => s == BluetoothConnectionState.connected).first.timeout(const Duration(seconds: 10));
      if (Platform.isAndroid) {
        await device.bleDevice.requestMtu(512);
        await device.bleDevice.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.high);
      }
      _services = await device.bleDevice.discoverServices();
      _connectedDevice = device;
      _reconnectAttempts = 0;
      await _readDeviceInfo();
      _updateConnectionState(DeviceConnectionState.connected);
      _startBatteryListener();
      _startConnectionWatchdog();
      print('BLE connected to ${device.name}');
      return true;
    } catch (e) {
      print('BLE connection error: $e');
      _updateConnectionState(DeviceConnectionState.disconnected);
      if (_shouldReconnect) _scheduleReconnect();
      return false;
    }
  }

  void _startConnectionWatchdog() {
    _connectionWatchdog?.cancel();
    _connectionWatchdog = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_connectedDevice != null && _connectionState == DeviceConnectionState.connected) {
        try {
          final isConnected = _connectedDevice!.bleDevice.isConnected;
          if (!isConnected) {
            print('Watchdog: Device disconnected, triggering reconnect');
            _handleDisconnection();
          }
        } catch (e) {
          print('Watchdog error: $e');
        }
      }
    });
  }

  void _handleDisconnection() {
    print('BLE disconnected');
    _connectionWatchdog?.cancel();
    _audioSubscription?.cancel();
    _audioSubscription = null;
    _batterySubscription?.cancel();
    _batterySubscription = null;
    final wasConnected = _connectionState == DeviceConnectionState.connected || _connectionState == DeviceConnectionState.streaming;
    _connectedDevice = null;
    _services = [];
    _updateConnectionState(DeviceConnectionState.disconnected);
    if (_shouldReconnect && wasConnected) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _reconnectAttempts >= _maxReconnectAttempts || _lastConnectedDeviceId == null) {
      print('BLE: Max retries reached or reconnect disabled');
      return;
    }
    _reconnectTimer?.cancel();
    final delay = Duration(milliseconds: min(2000 * pow(1.3, _reconnectAttempts).toInt(), 60000));
    print('BLE: Reconnecting in ${delay.inSeconds}s (attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts)');
    _reconnectTimer = Timer(delay, () async {
      _reconnectAttempts++;
      if (_lastConnectedDeviceId != null) {
        final bleDevice = BluetoothDevice.fromId(_lastConnectedDeviceId!);
        final device = OmiDevice(id: _lastConnectedDeviceId!, name: 'OMI Device', rssi: 0, bleDevice: bleDevice);
        await _connectToDevice(device);
      }
    });
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _connectionWatchdog?.cancel();
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
        print('BLE disconnect error: $e');
      }
    }
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
    if (codecData.isNotEmpty) _connectedDevice!.codec = BleAudioCodec.fromId(codecData[0]);
    final batteryData = await _readCharacteristic(batteryServiceUuid, batteryLevelCharacteristicUuid);
    if (batteryData.isNotEmpty) {
      _connectedDevice!.batteryLevel = batteryData[0];
      _batteryController.add(batteryData[0]);
    }
    final firmwareData = await _readCharacteristic(deviceInformationServiceUuid, firmwareRevisionCharacteristicUuid);
    if (firmwareData.isNotEmpty) _connectedDevice!.firmwareVersion = String.fromCharCodes(firmwareData);
  }

  Future<List<int>> _readCharacteristic(String serviceUuid, String charUuid) async {
    try {
      final service = _services.firstWhereOrNull((s) => s.uuid.str128.toLowerCase() == serviceUuid.toLowerCase());
      if (service == null) return [];
      final char = service.characteristics.firstWhereOrNull((c) => c.uuid.str128.toLowerCase() == charUuid.toLowerCase());
      if (char == null) return [];
      return await char.read();
    } catch (e) {
      print('Read characteristic error: $e');
      return [];
    }
  }

  void _startBatteryListener() async {
    try {
      final service = _services.firstWhereOrNull((s) => s.uuid.str128.toLowerCase() == batteryServiceUuid.toLowerCase());
      if (service == null) return;
      final char = service.characteristics.firstWhereOrNull((c) => c.uuid.str128.toLowerCase() == batteryLevelCharacteristicUuid.toLowerCase());
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
      final service = _services.firstWhereOrNull((s) => s.uuid.str128.toLowerCase() == omiServiceUuid.toLowerCase());
      if (service == null) {
        print('OMI service not found');
        return;
      }
      final char = service.characteristics.firstWhereOrNull((c) => c.uuid.str128.toLowerCase() == audioDataStreamCharacteristicUuid.toLowerCase());
      if (char == null) {
        print('Audio characteristic not found');
        return;
      }
      await char.setNotifyValue(true);
      _audioSubscription = char.lastValueStream.listen((value) {
        if (value.isNotEmpty) _audioDataController.add(value);
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
    if (_connectionState == DeviceConnectionState.streaming) _updateConnectionState(DeviceConnectionState.connected);
    print('Audio stream stopped');
  }

  BleAudioCodec? get currentCodec => _connectedDevice?.codec;

  void dispose() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _connectionWatchdog?.cancel();
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
