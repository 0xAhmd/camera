import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/streaming_service.dart';

/// Scans the QR code shown by the desktop app
/// QR encodes: phonecam://192.168.1.100:8765
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final MobileScannerController _scanner = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_scanned) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null) return;

    // Parse phonecam://IP:PORT
    final uri = Uri.tryParse(code);
    if (uri == null || uri.scheme != 'phonecam') return;

    setState(() => _scanned = true);
    await _scanner.stop();

    if (!mounted) return;
    final ip = uri.host;
    final port = uri.port;

    // Show confirmation and go back to stream
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).extension<AppColors>()!.card,
        title: Text(
          'Connect to desktop?',
          style: TextStyle(
            color: Theme.of(context).extension<AppColors>()!.text,
          ),
        ),
        content: Text(
          '$ip:$port',
          style: TextStyle(
            color: Theme.of(context).extension<AppColors>()!.accent,
            fontFamily: 'monospace',
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _scanned = false);
              Navigator.pop(context);
              _scanner.start();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // close scanner
              // Start streaming (the phone is the server, desktop connects)
              await context.read<StreamingService>().startStreaming();
            },
            child: Text(
              'Connect',
              style: TextStyle(
                color: Theme.of(context).extension<AppColors>()!.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan Desktop QR'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: _onDetect,
          ),
          // Overlay guide frame
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: c.accent, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // Instructions
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Point camera at the QR code\nshown in the desktop app',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.text, fontSize: 15, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
