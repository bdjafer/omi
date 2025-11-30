import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/ble_constants.dart';

enum WebSocketState { disconnected, connecting, connected }

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  WebSocketState _state = WebSocketState.disconnected;
  WebSocketState get state => _state;
  final _stateController = StreamController<WebSocketState>.broadcast();
  Stream<WebSocketState> get stateStream => _stateController.stream;
  String _serverUrl = 'ws://localhost:8000';
  String get serverUrl => _serverUrl;
  int _bytesSent = 0;
  int get bytesSent => _bytesSent;
  final _bytesController = StreamController<int>.broadcast();
  Stream<int> get bytesStream => _bytesController.stream;
  BleAudioCodec? _codec;
  int _sampleRate = 16000;
  int _retryCount = 0;
  static const int _maxRetries = 10;
  Timer? _reconnectTimer;
  Timer? _keepAliveTimer;
  bool _shouldReconnect = false;

  void setServerUrl(String url) {
    _serverUrl = url;
  }

  Future<bool> connect({required BleAudioCodec codec, int sampleRate = 16000}) async {
    _codec = codec;
    _sampleRate = sampleRate;
    _shouldReconnect = true;
    return await _connect();
  }

  Future<bool> _connect() async {
    if (_state == WebSocketState.connected) return true;
    if (_state == WebSocketState.connecting) return false;
    _updateState(WebSocketState.connecting);
    try {
      final wsUrl = '$_serverUrl/ws/audio?sample_rate=$_sampleRate&codec=$_codec';
      print('WebSocket connecting to: $wsUrl');
      _channel = IOWebSocketChannel.connect(wsUrl, pingInterval: const Duration(seconds: 10), connectTimeout: const Duration(seconds: 15));
      await _channel!.ready;
      _retryCount = 0;
      _updateState(WebSocketState.connected);
      _startKeepAlive();
      _channel!.stream.listen(
        (message) => print('WebSocket message: $message'),
        onError: (error) {
          print('WebSocket error: $error');
          _handleDisconnection();
        },
        onDone: () {
          print('WebSocket closed');
          _handleDisconnection();
        },
      );
      print('WebSocket connected');
      return true;
    } catch (e) {
      print('WebSocket connection error: $e');
      _updateState(WebSocketState.disconnected);
      _scheduleReconnect();
      return false;
    }
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_state == WebSocketState.connected) {
        try {
          _channel?.sink.add([0x8A, 0x00]);
        } catch (e) {
          print('Keep-alive failed: $e');
        }
      }
    });
  }

  void sendAudioData(List<int> data) {
    if (_state != WebSocketState.connected || _channel == null) return;
    try {
      _channel!.sink.add(data);
      _bytesSent += data.length;
      _bytesController.add(_bytesSent);
    } catch (e) {
      print('Send error: $e');
      _handleDisconnection();
    }
  }

  void _handleDisconnection() {
    _keepAliveTimer?.cancel();
    _channel = null;
    if (_state != WebSocketState.disconnected) {
      _updateState(WebSocketState.disconnected);
      if (_shouldReconnect) _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _retryCount >= _maxRetries) {
      print('WebSocket: Max retries reached or reconnect disabled');
      return;
    }
    _reconnectTimer?.cancel();
    final delay = Duration(milliseconds: min(1000 * pow(1.5, _retryCount).toInt(), 30000));
    print('WebSocket: Reconnecting in ${delay.inSeconds}s (attempt ${_retryCount + 1}/$_maxRetries)');
    _reconnectTimer = Timer(delay, () {
      _retryCount++;
      _connect();
    });
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _keepAliveTimer?.cancel();
    if (_channel != null) {
      try {
        await _channel!.sink.close();
      } catch (e) {
        print('WebSocket close error: $e');
      }
    }
    _channel = null;
    _bytesSent = 0;
    _updateState(WebSocketState.disconnected);
    print('WebSocket disconnected');
  }

  void _updateState(WebSocketState state) {
    _state = state;
    _stateController.add(state);
  }

  void dispose() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _keepAliveTimer?.cancel();
    _channel?.sink.close();
    _stateController.close();
    _bytesController.close();
  }
}
