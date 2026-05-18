// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/streaming_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final service = context.watch<StreamingService>();

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: c.bg,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionHeader('Video Quality', colors: c),
          const SizedBox(height: 12),

          _SettingsCard(
            colors: c,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label('Resolution', colors: c),
                const SizedBox(height: 8),
                _SegmentRow<ResolutionPreset>(
                  options: const [
                    (ResolutionPreset.low, '480p'),
                    (ResolutionPreset.high, '720p'),
                    (ResolutionPreset.veryHigh, '1080p'),
                  ],
                  selected: service.resolution,
                  onSelect: service.setResolution,
                  colors: c,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          _SettingsCard(
            colors: c,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label('Frame Rate', colors: c),
                const SizedBox(height: 8),
                _SegmentRow<int>(
                  options: const [
                    (30, '30 fps'),
                    (60, '60 fps'),
                  ],
                  selected: service.targetFps,
                  onSelect: service.setTargetFps,
                  colors: c,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _SectionHeader('About', colors: c),
          const SizedBox(height: 12),

          _SettingsCard(
            colors: c,
            child: Column(
              children: [
                _InfoRow('Version', '1.0.0', colors: c),
                Divider(color: c.surface, height: 1),
                _InfoRow('Protocol', 'MJPEG over WebSocket', colors: c),
                Divider(color: c.surface, height: 1),
                _InfoRow('Port', '8765', colors: c),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _SectionHeader('Desktop Setup', colors: c),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.accent.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Required on Windows:',
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                _BulletItem('Install OBS Studio (free) — provides the virtual camera driver', colors: c),
                _BulletItem('Install Node.js 18+', colors: c),
                _BulletItem('Install FFmpeg and add to PATH', colors: c),
                _BulletItem('Run desktop_app: npm install && npm start', colors: c),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {required this.colors});
  final String title;
  final AppColors colors;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: TextStyle(
      color: colors.muted,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child, required this.colors});
  final Widget child;
  final AppColors colors;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: colors.card,
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.colors});
  final String text;
  final AppColors colors;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: colors.muted,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    ),
  );
}

class _SegmentRow<T> extends StatelessWidget {
  const _SegmentRow({
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.colors,
  });
  final List<(T, String)> options;
  final T selected;
  final void Function(T) onSelect;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.map((opt) {
        final isSelected = opt.$1 == selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelect(opt.$1),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? colors.accent : colors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                opt.$2,
                style: TextStyle(
                  color: isSelected ? Colors.black : colors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {required this.colors});
  final String label;
  final String value;
  final AppColors colors;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Text(label, style: TextStyle(color: colors.muted, fontSize: 14)),
        const Spacer(),
        Text(value, style: TextStyle(color: colors.text, fontSize: 14)),
      ],
    ),
  );
}

class _BulletItem extends StatelessWidget {
  const _BulletItem(this.text, {required this.colors});
  final String text;
  final AppColors colors;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('·  ', style: TextStyle(color: colors.accent, fontSize: 14)),
        Expanded(
          child: Text(text, style: TextStyle(color: colors.text, fontSize: 13)),
        ),
      ],
    ),
  );
}
