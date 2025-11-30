import 'dart:async';
import '../models/omi_device.dart';
import 'ble_service.dart';
import 'websocket_service.dart';

class AudioStreamer {
  static final AudioStreamer _instance = AudioStreamer._internal();
  factory AudioStreamer() => _instance;
  AudioStreamer._internal();

  final BleService _bleService = BleService();
  final WebSocketService _wsService = WebSocketService();
  StreamSubscription? _audioSubscription;
  StreamSubscription? _bleStateSubscription;
  StreamSubscription? _wsStateSubscription;
  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;
  bool _shouldStream = false;
  final _streamingController = StreamController<bool>.broadcast();
  Stream<bool> get streamingStream => _streamingController.stream;

  void init() {
    _bleStateSubscription = _bleService.connectionStateStream.listen((state) {
      if (_shouldStream) {
        if (state == DeviceConnectionState.connected && !_isStreaming) {
          _resumeStreaming();
        } else if (state == DeviceConnectionState.disconnected && _isStreaming) {
          _pauseStreaming();
        }
      }
    });
    _wsStateSubscription = _wsService.stateStream.listen((state) {
      if (_shouldStream && state == WebSocketState.connected && _bleService.connectionState == DeviceConnectionState.streaming) {
        _subscribeToAudio();
      }
    });
  }

  Future<bool> startStreaming() async {
    if (_isStreaming) return true;
    if (_bleService.connectedDevice == null) {
      print('AudioStreamer: No device connected');
      return false;
    }
    _shouldStream = true;
    final codec = _bleService.currentCodec!;
    final connected = await _wsService.connect(codec: codec, sampleRate: codec.sampleRate);
    if (!connected) {
      print('AudioStreamer: WebSocket connection failed, will retry');
    }
    await _bleService.startAudioStream();
    _subscribeToAudio();
    _isStreaming = true;
    _streamingController.add(true);
    print('AudioStreamer: Streaming started');
    return true;
  }

  void _subscribeToAudio() {
    _audioSubscription?.cancel();
    _audioSubscription = _bleService.audioDataStream.listen((data) {
      if (_wsService.state == WebSocketState.connected) {
        _wsService.sendAudioData(data);
      }
    });
  }

  Future<void> _resumeStreaming() async {
    print('AudioStreamer: Resuming streaming after reconnect');
    if (_bleService.connectedDevice == null) return;
    final codec = _bleService.currentCodec!;
    await _wsService.connect(codec: codec, sampleRate: codec.sampleRate);
    await _bleService.startAudioStream();
    _subscribeToAudio();
    _isStreaming = true;
    _streamingController.add(true);
  }

  void _pauseStreaming() {
    print('AudioStreamer: Pausing streaming due to disconnect');
    _audioSubscription?.cancel();
    _audioSubscription = null;
    _isStreaming = false;
    _streamingController.add(false);
  }

  Future<void> stopStreaming() async {
    _shouldStream = false;
    _audioSubscription?.cancel();
    _audioSubscription = null;
    await _bleService.stopAudioStream();
    await _wsService.disconnect();
    _isStreaming = false;
    _streamingController.add(false);
    print('AudioStreamer: Streaming stopped');
  }

  void dispose() {
    _shouldStream = false;
    _audioSubscription?.cancel();
    _bleStateSubscription?.cancel();
    _wsStateSubscription?.cancel();
    _streamingController.close();
  }
}
