import 'dart:async';
import 'package:flutter/material.dart';
import '../models/omi_device.dart';
import '../services/ble_service.dart';
import '../services/websocket_service.dart';
import '../services/audio_streamer.dart';
import '../services/foreground_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BleService _bleService = BleService();
  final WebSocketService _wsService = WebSocketService();
  final AudioStreamer _audioStreamer = AudioStreamer();
  final ForegroundServiceManager _foregroundService = ForegroundServiceManager();
  final TextEditingController _serverController = TextEditingController(text: 'wss://739c26ef1c8b.ngrok-free.app');
  List<OmiDevice> _devices = [];
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  WebSocketState _wsState = WebSocketState.disconnected;
  bool _isScanning = false;
  bool _isStreaming = false;
  int _batteryLevel = -1;
  int _bytesSent = 0;
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    _subscriptions.add(_bleService.devicesStream.listen((devices) => setState(() => _devices = devices)));
    _subscriptions.add(_bleService.connectionStateStream.listen((state) {
      setState(() => _connectionState = state);
      _updateNotification();
    }));
    _subscriptions.add(_wsService.stateStream.listen((state) {
      setState(() => _wsState = state);
      _updateNotification();
    }));
    _subscriptions.add(_audioStreamer.streamingStream.listen((streaming) {
      setState(() => _isStreaming = streaming);
      _updateNotification();
    }));
    _subscriptions.add(_bleService.batteryStream.listen((level) => setState(() => _batteryLevel = level)));
    _subscriptions.add(_wsService.bytesStream.listen((bytes) => setState(() => _bytesSent = bytes)));
  }

  void _updateNotification() {
    if (_isStreaming) {
      final status = _wsState == WebSocketState.connected ? 'Connected' : 'Reconnecting...';
      _foregroundService.updateNotification('Streaming - $status - ${_formatBytes(_bytesSent)}');
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    await _bleService.startScan(timeout: 10);
    setState(() => _isScanning = false);
  }

  Future<void> _connectDevice(OmiDevice device) async {
    await _bleService.connect(device);
    if (_bleService.connectedDevice != null) {
      setState(() => _batteryLevel = _bleService.connectedDevice!.batteryLevel);
    }
  }

  Future<void> _disconnect() async {
    if (_isStreaming) await _stopStreaming();
    await _bleService.disconnect();
  }

  Future<void> _startStreaming() async {
    _wsService.setServerUrl(_serverController.text);
    await _foregroundService.start();
    await _audioStreamer.startStreaming();
  }

  Future<void> _stopStreaming() async {
    await _audioStreamer.stopStreaming();
    await _foregroundService.stop();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Minimal OMI'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildServerConfig(),
            const SizedBox(height: 16),
            _buildConnectionStatus(),
            const SizedBox(height: 16),
            if (_connectionState == DeviceConnectionState.disconnected) _buildScanSection() else ...[_buildDeviceInfo(), const SizedBox(height: 16), _buildStreamingSection()],
          ],
        ),
      ),
    );
  }

  Widget _buildServerConfig() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Backend Server (WebSocket)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _serverController,
              decoration: const InputDecoration(hintText: 'wss://739c26ef1c8b.ngrok-free.app', border: OutlineInputBorder(), isDense: true),
              enabled: !_isStreaming,
            ),
            const SizedBox(height: 8),
            Text('Use wss:// for ngrok, ws:// for local', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    final deviceConnected = _connectionState != DeviceConnectionState.disconnected;
    final wsConnected = _wsState == WebSocketState.connected;
    final wsConnecting = _wsState == WebSocketState.connecting;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusIndicator('BLE Device', deviceConnected, _connectionState == DeviceConnectionState.connecting),
                _buildStatusIndicator('WebSocket', wsConnected, wsConnecting),
                _buildStatusIndicator('Streaming', _isStreaming, false),
              ],
            ),
            if (_isStreaming && !wsConnected) ...[
              const SizedBox(height: 8),
              Text('WebSocket reconnecting...', style: TextStyle(color: Colors.orange[300], fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(String label, bool active, bool loading) {
    return Column(
      children: [
        if (loading)
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
        else
          Icon(active ? Icons.check_circle : Icons.cancel, color: active ? Colors.green : Colors.red, size: 24),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildScanSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Scan for OMI Devices', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: _isScanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.bluetooth_searching),
                  label: Text(_isScanning ? 'Scanning...' : 'Scan'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_devices.isEmpty)
              const Center(child: Text('No devices found', style: TextStyle(color: Colors.grey)))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  return ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(device.name),
                    subtitle: Text('RSSI: ${device.rssi} dBm'),
                    trailing: ElevatedButton(onPressed: () => _connectDevice(device), child: const Text('Connect')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfo() {
    final device = _bleService.connectedDevice;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Connected Device', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.bluetooth_disabled, color: Colors.red),
                  label: const Text('Disconnect', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildInfoRow('Name', device?.name ?? 'Unknown'),
            _buildInfoRow('Codec', device?.codec.toString() ?? 'Unknown'),
            _buildInfoRow('Firmware', device?.firmwareVersion ?? 'Unknown'),
            _buildInfoRow('Battery', _batteryLevel >= 0 ? '$_batteryLevel%' : 'Unknown'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: Colors.grey)), Text(value)]),
    );
  }

  Widget _buildStreamingSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Audio Streaming', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (_isStreaming) ...[
              _buildInfoRow('Status', _wsState == WebSocketState.connected ? 'Streaming' : 'Reconnecting...'),
              _buildInfoRow('Bytes Sent', _formatBytes(_bytesSent)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Running in background. Will auto-reconnect if disconnected.', style: TextStyle(fontSize: 12, color: Colors.green[300]))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            ElevatedButton.icon(
              onPressed: _connectionState == DeviceConnectionState.connected || _connectionState == DeviceConnectionState.streaming || _isStreaming ? (_isStreaming ? _stopStreaming : _startStreaming) : null,
              icon: Icon(_isStreaming ? Icons.stop : Icons.play_arrow),
              label: Text(_isStreaming ? 'Stop Streaming' : 'Start Streaming'),
              style: ElevatedButton.styleFrom(backgroundColor: _isStreaming ? Colors.red : Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
