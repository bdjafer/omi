import 'dart:async';
import 'ble_service.dart';
import 'websocket_service.dart';

class AudioStreamer {
  static final AudioStreamer _instance = AudioStreamer._internal();
  factory AudioStreamer() => _instance;
  AudioStreamer._internal();

  final BleService _bleService = BleService();
  final WebSocketService _wsService = WebSocketService();
  StreamSubscription? _audioSubscription;
  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;
  final _streamingController = StreamController<bool>.broadcast();
  Stream<bool> get streamingStream => _streamingController.stream;

  Future<bool> startStreaming() async {
    if (_isStreaming) return true;
    if (_bleService.connectedDevice == null) {
      print('No device connected');
      return false;
    }
    final codec = _bleService.currentCodec!;
    final connected = await _wsService.connect(codec: codec, sampleRate: codec.sampleRate);
    if (!connected) {
      print('WebSocket connection failed');
      return false;
    }
    await _bleService.startAudioStream();
    _audioSubscription = _bleService.audioDataStream.listen((data) {
      _wsService.sendAudioData(data);
    });
    _isStreaming = true;
    _streamingController.add(true);
    print('Audio streaming started');
    return true;
  }

  Future<void> stopStreaming() async {
    _audioSubscription?.cancel();
    _audioSubscription = null;
    await _bleService.stopAudioStream();
    await _wsService.disconnect();
    _isStreaming = false;
    _streamingController.add(false);
    print('Audio streaming stopped');
  }

  void dispose() {
    _audioSubscription?.cancel();
    _streamingController.close();
  }
}

