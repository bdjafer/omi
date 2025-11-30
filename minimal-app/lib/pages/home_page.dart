import 'dart:async';
import 'package:flutter/material.dart';
import '../models/omi_device.dart';
import '../services/ble_service.dart';
import '../services/websocket_service.dart';
import '../services/audio_streamer.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BleService _bleService = BleService();
  final WebSocketService _wsService = WebSocketService();
  final AudioStreamer _audioStreamer = AudioStreamer();
  final TextEditingController _serverController = TextEditingController(text: 'ws://10.0.2.2:8000');
  List<OmiDevice> _devices = [];
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  WebSocketState _wsState = WebSocketState.disconnected;
  bool _isScanning = false;
  bool _isStreaming = false;
  int _batteryLevel = -1;
  int _bytesSent = 0;
  StreamSubscription? _devicesSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _wsStateSubscription;
  StreamSubscription? _streamingSubscription;
  StreamSubscription? _batterySubscription;
  StreamSubscription? _bytesSubscription;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    _devicesSubscription = _bleService.devicesStream.listen((devices) {
      setState(() => _devices = devices);
    });
    _connectionSubscription = _bleService.connectionStateStream.listen((state) {
      setState(() => _connectionState = state);
    });
    _wsStateSubscription = _wsService.stateStream.listen((state) {
      setState(() => _wsState = state);
    });
    _streamingSubscription = _audioStreamer.streamingStream.listen((streaming) {
      setState(() => _isStreaming = streaming);
    });
    _batterySubscription = _bleService.batteryStream.listen((level) {
      setState(() => _batteryLevel = level);
    });
    _bytesSubscription = _wsService.bytesStream.listen((bytes) {
      setState(() => _bytesSent = bytes);
    });
  }

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    _connectionSubscription?.cancel();
    _wsStateSubscription?.cancel();
    _streamingSubscription?.cancel();
    _batterySubscription?.cancel();
    _bytesSubscription?.cancel();
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
    if (_isStreaming) await _audioStreamer.stopStreaming();
    await _bleService.disconnect();
  }

  Future<void> _toggleStreaming() async {
    if (_isStreaming) {
      await _audioStreamer.stopStreaming();
    } else {
      _wsService.setServerUrl(_serverController.text);
      await _audioStreamer.startStreaming();
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minimal OMI'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildServerConfig(),
            const SizedBox(height: 16),
            _buildConnectionStatus(),
            const SizedBox(height: 16),
            if (_connectionState == DeviceConnectionState.disconnected) ...[
              _buildScanSection(),
            ] else ...[
              _buildDeviceInfo(),
              const SizedBox(height: 16),
              _buildStreamingSection(),
            ],
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
            const Text('Backend Server', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _serverController,
              decoration: const InputDecoration(
                hintText: 'ws://localhost:8000',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              enabled: !_isStreaming,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    final deviceConnected = _connectionState != DeviceConnectionState.disconnected;
    final wsConnected = _wsState == WebSocketState.connected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatusIndicator('Device', deviceConnected, _connectionState == DeviceConnectionState.connecting),
            _buildStatusIndicator('WebSocket', wsConnected, _wsState == WebSocketState.connecting),
            _buildStatusIndicator('Streaming', _isStreaming, false),
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
          Icon(
            active ? Icons.check_circle : Icons.cancel,
            color: active ? Colors.green : Colors.red,
            size: 24,
          ),
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
                  icon: _isScanning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bluetooth_searching),
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
                    trailing: ElevatedButton(
                      onPressed: () => _connectDevice(device),
                      child: const Text('Connect'),
                    ),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value),
        ],
      ),
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
              _buildInfoRow('Status', 'Streaming'),
              _buildInfoRow('Bytes Sent', _formatBytes(_bytesSent)),
              const SizedBox(height: 16),
            ],
            ElevatedButton.icon(
              onPressed: _connectionState == DeviceConnectionState.connected || _isStreaming ? _toggleStreaming : null,
              icon: Icon(_isStreaming ? Icons.stop : Icons.play_arrow),
              label: Text(_isStreaming ? 'Stop Streaming' : 'Start Streaming'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isStreaming ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

