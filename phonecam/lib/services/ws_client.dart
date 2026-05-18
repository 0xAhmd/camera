import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// WsClient
/// 
/// Connects the phone to the desktop WebSocket server.
/// Used in Mode A (QR connect): phone connects TO desktop.
/// 
/// The desktop is the WebSocket server (port 9001).
/// The phone sends JPEG frames as binary messages.
/// The desktop sends JSON control commands as text.
class WsClient {
  WsClient({
    required this.ip,
    required this.port,
    required this.onFrame,
    required this.onControl,
    required this.onConnected,
    required this.onDisconnected,
  });

  final String ip;
  final int port;
  final void Function(Uint8List frame) onFrame;
  final void Function(Map<String, dynamic> cmd) onControl;
  final void Function() onConnected;
  final void Function() onDisconnected;

  IOWebSocketChannel? _channel;
  bool _isConnected = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  Future<void> connect() async {
    _shouldReconnect = true;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    try {
      debugPrint('[WsClient] Connecting to ws://$ip:$port');
      _channel = IOWebSocketChannel.connect(
        Uri.parse('ws://$ip:$port'),
        connectTimeout: const Duration(seconds: 5),
        pingInterval: const Duration(seconds: 5),
      );

      await _channel!.ready;
      _isConnected = true;
      _reconnectAttempts = 0;
      onConnected();
      debugPrint('[WsClient] Connected to desktop');

      _channel!.stream.listen(
        (data) {
          if (data is List<int>) {
            onFrame(Uint8List.fromList(data));
          } else if (data is Uint8List) {
            onFrame(data);
          } else if (data is String) {
            try {
              // Control command from desktop
              // Not commonly used — desktop controls phone
            } catch (_) {}
          }
        },
        onDone: () {
          _isConnected = false;
          onDisconnected();
          _scheduleReconnect();
        },
        onError: (e) {
          debugPrint('[WsClient] Error: $e');
          _isConnected = false;
          onDisconnected();
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[WsClient] Connection failed: $e');
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  /// Send a JPEG frame to the desktop
  void sendFrame(Uint8List jpegBytes) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jpegBytes);
      } catch (e) {
        debugPrint('[WsClient] Send frame error: $e');
      }
    }
  }

  /// Send a text control message
  void sendControl(Map<String, dynamic> msg) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(msg.toString());
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts.clamp(1, 10));
    debugPrint('[WsClient] Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(delay, _doConnect);
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }

  bool get isConnected => _isConnected;
}
