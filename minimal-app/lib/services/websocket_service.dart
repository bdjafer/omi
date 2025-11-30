import 'dart:async';
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

  void setServerUrl(String url) {
    _serverUrl = url;
  }

  Future<bool> connect({required BleAudioCodec codec, int sampleRate = 16000}) async {
    if (_state == WebSocketState.connected || _state == WebSocketState.connecting) {
      return _state == WebSocketState.connected;
    }
    _updateState(WebSocketState.connecting);
    _bytesSent = 0;
    try {
      final wsUrl = '$_serverUrl/ws/audio?sample_rate=$sampleRate&codec=$codec';
      print('Connecting to WebSocket: $wsUrl');
      _channel = IOWebSocketChannel.connect(
        wsUrl,
        pingInterval: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 10),
      );
      await _channel!.ready;
      _channel!.stream.listen(
        (message) {
          print('WebSocket message: $message');
        },
        onError: (error) {
          print('WebSocket error: $error');
          _handleDisconnection();
        },
        onDone: () {
          print('WebSocket closed');
          _handleDisconnection();
        },
      );
      _updateState(WebSocketState.connected);
      print('WebSocket connected');
      return true;
    } catch (e) {
      print('WebSocket connection error: $e');
      _updateState(WebSocketState.disconnected);
      return false;
    }
  }

  void sendAudioData(List<int> data) {
    if (_state != WebSocketState.connected || _channel == null) return;
    try {
      _channel!.sink.add(data);
      _bytesSent += data.length;
      _bytesController.add(_bytesSent);
    } catch (e) {
      print('Send error: $e');
    }
  }

  Future<void> disconnect() async {
    if (_channel != null) {
      try {
        await _channel!.sink.close();
      } catch (e) {
        print('WebSocket close error: $e');
      }
    }
    _channel = null;
    _updateState(WebSocketState.disconnected);
    print('WebSocket disconnected');
  }

  void _handleDisconnection() {
    _channel = null;
    _updateState(WebSocketState.disconnected);
  }

  void _updateState(WebSocketState state) {
    _state = state;
    _stateController.add(state);
  }

  void dispose() {
    _channel?.sink.close();
    _stateController.close();
    _bytesController.close();
  }
}

