import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// The core service that:
/// 1. Opens the camera
/// 2. Encodes frames as JPEG
/// 3. Serves them over a WebSocket on port 8765
/// 4. Handles reconnection and background keep-alive
class StreamingService extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────────
  StreamingState _state = StreamingState.idle;
  StreamingState get state => _state;

  String? _localIp;
  String? get localIp => _localIp;

  int _connectedClients = 0;
  int get connectedClients => _connectedClients;

  double _fps = 0;
  double get fps => _fps;

  CameraDescription? _currentCamera;
  bool _isFrontCamera = false;

  // ── Settings ───────────────────────────────────────────────────────────────
  ResolutionPreset _resolution = ResolutionPreset.high; // 720p default
  ResolutionPreset get resolution => _resolution;

  int _targetFps = 30;
  int get targetFps => _targetFps;

  final int _jpegQuality = 80; // 0-100

  // ── Internals ─────────────────────────────────────────────────────────────
  CameraController? cameraController;
  HttpServer? _httpServer;
  final Set<WebSocket> _clients = {};

  // FPS tracking
  int _frameCount = 0;
  DateTime _fpsTimer = DateTime.now();

  // Frame throttle
  DateTime _lastFrameSent = DateTime.now();
  Duration get _frameInterval => Duration(milliseconds: (1000 / _targetFps).round());

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> startStreaming() async {
    if (_state == StreamingState.streaming) return;
    _setState(StreamingState.starting);

    try {
      await _initCamera();
      await _startWebSocketServer();
      await WakelockPlus.enable();
      _localIp = await NetworkInfo().getWifiIP();
      _setState(StreamingState.streaming);
    } catch (e) {
      debugPrint('Start streaming error: $e');
      _setState(StreamingState.error);
    }
  }

  Future<void> stopStreaming() async {
    await _stopAll();
    _setState(StreamingState.idle);
  }

  Future<void> switchCamera() async {
    _isFrontCamera = !_isFrontCamera;
    await _restartCamera();
  }

  Future<void> setResolution(ResolutionPreset preset) async {
    _resolution = preset;
    if (_state == StreamingState.streaming) {
      await _restartCamera();
    }
    notifyListeners();
  }

  void setTargetFps(int fps) {
    _targetFps = fps;
    notifyListeners();
  }

  // ── Camera ─────────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw Exception('No cameras found');

    _currentCamera = cameras.firstWhere(
      (c) => _isFrontCamera
          ? c.lensDirection == CameraLensDirection.front
          : c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    await cameraController?.dispose();
    cameraController = CameraController(
      _currentCamera!,
      _resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg, // JPEG straight from camera
    );

    await cameraController!.initialize();

    // Start frame stream
    await cameraController!.startImageStream(_onCameraFrame);
  }

  void _onCameraFrame(CameraImage frame) {
    final now = DateTime.now();

    // Throttle to target FPS
    if (now.difference(_lastFrameSent) < _frameInterval) return;
    _lastFrameSent = now;

    // Skip if no clients connected
    if (_clients.isEmpty) return;

    // Encode and broadcast in an isolate to avoid blocking UI thread
    _encodeAndBroadcast(frame);

    // FPS tracking
    _frameCount++;
    if (now.difference(_fpsTimer).inSeconds >= 1) {
      _fps = _frameCount / now.difference(_fpsTimer).inSeconds;
      _frameCount = 0;
      _fpsTimer = now;
      notifyListeners();
    }
  }

  Future<void> _encodeAndBroadcast(CameraImage frame) async {
    try {
      Uint8List? jpegBytes;

      if (frame.format.group == ImageFormatGroup.jpeg) {
        // Camera already gave us JPEG (Android with JPEG format group)
        jpegBytes = frame.planes[0].bytes;
      } else {
        // Convert YUV420 to JPEG via compute isolate
        jpegBytes = await compute(_convertYuvToJpeg, {
          'width': frame.width,
          'height': frame.height,
          'yPlane': frame.planes[0].bytes,
          'uPlane': frame.planes[1].bytes,
          'vPlane': frame.planes[2].bytes,
          'quality': _jpegQuality,
        });
      }

      if (jpegBytes == null || jpegBytes.isEmpty) return;

      // Build MJPEG frame: binary message = just raw JPEG bytes
      // Desktop receives, decodes, renders
      final deadClients = <WebSocket>[];
      for (final client in _clients) {
        try {
          client.add(jpegBytes);
        } catch (_) {
          deadClients.add(client);
        }
      }
      for (final dc in deadClients) {
        _clients.remove(dc);
        _connectedClients = _clients.length;
      }
    } catch (e) {
      debugPrint('Frame encode error: $e');
    }
  }

  // ── WebSocket Server ────────────────────────────────────────────────────────

  Future<void> _startWebSocketServer() async {
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 8765);
    debugPrint('WebSocket server listening on port 8765');

    _httpServer!.transform(WebSocketTransformer()).listen(
      (WebSocket ws) {
        _clients.add(ws);
        _connectedClients = _clients.length;
        notifyListeners();
        debugPrint('Client connected. Total: $_connectedClients');

        ws.listen(
          (data) {
            // Handle control messages from desktop (camera switch, quality, etc.)
            if (data is String) _handleControlMessage(data);
          },
          onDone: () {
            _clients.remove(ws);
            _connectedClients = _clients.length;
            notifyListeners();
            debugPrint('Client disconnected. Total: $_connectedClients');
          },
          onError: (e) {
            _clients.remove(ws);
            _connectedClients = _clients.length;
            notifyListeners();
          },
          cancelOnError: true,
        );
      },
      onError: (e) => debugPrint('WebSocket server error: $e'),
    );
  }

  void _handleControlMessage(String msg) {
    // Simple JSON commands from desktop
    // e.g. {"cmd":"switch_camera"} or {"cmd":"set_quality","value":70}
    try {
      if (msg.contains('switch_camera')) switchCamera();
      if (msg.contains('set_fps_30')) setTargetFps(30);
      if (msg.contains('set_fps_60')) setTargetFps(60);
    } catch (_) {}
  }

  // ── Lifecycle / Recovery ───────────────────────────────────────────────────

  /// Called when app resumes from background
  Future<void> onResume() async {
    if (_state == StreamingState.streaming) {
      // Camera may have been released — reinitialize
      await _restartCamera();
    }
  }

  /// Called when app is paused (but foreground service keeps socket alive)
  Future<void> onPause() async {
    // Don't stop — foreground service will call onResume when needed
    // Camera image stream continues while we have the foreground service wakelock
  }

  Future<void> _restartCamera() async {
    try {
      await cameraController?.stopImageStream();
      await cameraController?.dispose();
      cameraController = null;
      await _initCamera();
    } catch (e) {
      debugPrint('Camera restart error: $e');
      // Retry after 1 second
      await Future.delayed(const Duration(seconds: 1));
      try {
        await _initCamera();
      } catch (e2) {
        debugPrint('Camera restart retry failed: $e2');
        _setState(StreamingState.error);
      }
    }
  }

  Future<void> _stopAll() async {
    await cameraController?.stopImageStream();
    await cameraController?.dispose();
    cameraController = null;

    for (final client in _clients) {
      await client.close();
    }
    _clients.clear();

    await _httpServer?.close();
    _httpServer = null;

    await WakelockPlus.disable();
    _connectedClients = 0;
    _fps = 0;
  }

  void _setState(StreamingState s) {
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopAll();
    super.dispose();
  }
}

// ── YUV → JPEG conversion (runs in isolate) ─────────────────────────────────

// ignore: unused_element
Uint8List? _convertYuvToJpeg(Map<String, dynamic> args) {
  // This is a stub — on Android with ImageFormatGroup.jpeg,
  // the camera already outputs JPEG so this won't be called.
  // If you need YUV conversion (e.g. older devices), use the
  // `image` package: Image img = Image(width, height); ... encodeJpg(img)
  return null;
}

// ── Enums ─────────────────────────────────────────────────────────────────────

enum StreamingState {
  idle,
  starting,
  streaming,
  error,
}
