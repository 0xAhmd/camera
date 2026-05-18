// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../main.dart';
import '../services/streaming_service.dart';
import '../services/foreground_service.dart';
import 'connect_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ForegroundServiceManager.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final service = context.read<StreamingService>();
    switch (state) {
      case AppLifecycleState.paused:
        service.onPause();
        break;
      case AppLifecycleState.resumed:
        service.onResume();
        break;
      default:
        break;
    }
  }

  Future<void> _toggleStreaming(StreamingService service) async {
    if (service.state == StreamingState.streaming) {
      await service.stopStreaming();
      await ForegroundServiceManager.stop();
    } else {
      await service.startStreaming();
      if (service.state == StreamingState.streaming) {
        await ForegroundServiceManager.start(
          ip: service.localIp ?? '0.0.0.0',
          port: 8765,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final service = context.watch<StreamingService>();
    final isStreaming = service.state == StreamingState.streaming;
    final isStarting = service.state == StreamingState.starting;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Text(
                    'PhoneCam',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.settings_outlined, color: c.muted),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),

            // ── Camera preview ──────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _CameraPreviewCard(service: service, colors: c),
              ),
            ),

            // ── Status row ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: _StatusRow(service: service, colors: c),
            ),

            // ── QR code (when streaming) ─────────────────────────────────
            if (isStreaming && service.localIp != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: _QrCard(ip: service.localIp!, colors: c),
              ),

            // ── Main action button ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: isStarting ? null : () => _toggleStreaming(service),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isStreaming ? Colors.red.shade700 : c.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: isStarting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            isStreaming ? 'Stop Streaming' : 'Start Streaming',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  if (!isStreaming)
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ConnectScreen()),
                      ),
                      child: Text(
                        'Scan QR from desktop',
                        style: TextStyle(color: c.accent, fontSize: 15),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Camera Preview Card ───────────────────────────────────────────────────────

class _CameraPreviewCard extends StatelessWidget {
  const _CameraPreviewCard({required this.service, required this.colors});
  final StreamingService service;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final controller = service.cameraController;
    final isReady = controller != null && controller.value.isInitialized;
    final isStreaming = service.state == StreamingState.streaming;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.card, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Actual camera preview ──────────────────────────────────────
          if (isReady)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.previewSize?.height ?? 1,
                  height: controller.value.previewSize?.width ?? 1,
                  child: CameraPreview(controller),
                ),
              ),
            )
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isStreaming
                        ? Icons.hourglass_empty_rounded
                        : Icons.videocam_off_outlined,
                    size: 64,
                    color: colors.muted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isStreaming ? 'Starting camera...' : 'Camera inactive',
                    style: TextStyle(color: colors.muted, fontSize: 16),
                  ),
                ],
              ),
            ),

          // ── Camera switch button ───────────────────────────────────────
          if (isReady)
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onTap: service.switchCamera,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.flip_camera_android_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),

          // ── FPS indicator ──────────────────────────────────────────────
          if (isReady)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${service.fps.toStringAsFixed(0)} fps',
                  style: TextStyle(
                    color:
                        service.fps >= 25 ? colors.accent : Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

          // ── LIVE badge ─────────────────────────────────────────────────
          if (isStreaming)
            Positioned(
              bottom: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Status Row ────────────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.service, required this.colors});
  final StreamingService service;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(
          icon: Icons.wifi,
          label: service.localIp ?? 'No IP',
          color: service.localIp != null ? colors.accent : colors.muted,
          colors: colors,
        ),
        const SizedBox(width: 8),
        _Chip(
          icon: Icons.devices,
          label: '${service.connectedClients} connected',
          color:
              service.connectedClients > 0 ? colors.accent : colors.muted,
          colors: colors,
        ),
        const SizedBox(width: 8),
        _Chip(
          icon: Icons.hd,
          label: _resLabel(service.resolution),
          color: colors.muted,
          colors: colors,
        ),
      ],
    );
  }

  String _resLabel(ResolutionPreset r) {
    switch (r) {
      case ResolutionPreset.low:
        return '480p';
      case ResolutionPreset.medium:
        return '540p';
      case ResolutionPreset.high:
        return '720p';
      case ResolutionPreset.veryHigh:
        return '1080p';
      default:
        return '720p';
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    required this.colors,
  });
  final IconData icon;
  final String label;
  final Color color;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── QR Card ───────────────────────────────────────────────────────────────────

class _QrCard extends StatelessWidget {
  const _QrCard({required this.ip, required this.colors});
  final String ip;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final connectionString = 'phonecam://$ip:8765';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surface, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: QrImageView(
              data: connectionString,
              size: 80,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scan from desktop',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ip,
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 14,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Or desktop will auto-discover',
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}