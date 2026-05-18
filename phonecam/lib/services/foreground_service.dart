import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Manages the Android foreground service that keeps the app alive
/// while streaming — even when the screen is locked or app is backgrounded.
class ForegroundServiceManager {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'phonecam_stream',
        channelName: 'PhoneCam Streaming',
        channelDescription: 'Camera is streaming to your PC',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
        buttons: [
          const NotificationButton(
            id: 'stop',
            text: 'Stop Streaming',
            textColor: Colors.red,
          ),
        ],
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000, // heartbeat every 5s
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,  // KEY: prevents CPU from sleeping
        allowWifiLock: true,  // KEY: prevents Wi-Fi from sleeping
      ),
    );
  }

  static Future<bool> start({required String ip, required int port}) async {
    await init();

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'PhoneCam Active',
        notificationText: 'Streaming to $ip:$port',
      );
      return true;
    }

    return FlutterForegroundTask.startService(
      notificationTitle: 'PhoneCam Active',
      notificationText: 'Streaming camera to PC...',
      callback: _foregroundTaskCallback,
    );
  }

  static Future<bool> stop() async {
    return FlutterForegroundTask.stopService();
  }

  static Future<bool> isRunning() async {
    return FlutterForegroundTask.isRunningService;
  }
}

/// This runs in a separate isolate — keep it light
@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_ForegroundTaskHandler());
}

class _ForegroundTaskHandler extends TaskHandler {
  int _heartbeat = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('Foreground task started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Heartbeat — just proves we're alive
    _heartbeat++;
    FlutterForegroundTask.updateService(
      notificationText: 'Streaming active · ${_heartbeat * 5}s',
    );

    // Send heartbeat to main isolate if needed
    FlutterForegroundTask.sendDataToMain(_heartbeat);
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('Foreground task destroyed');
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      // Signal main isolate to stop streaming
      FlutterForegroundTask.sendDataToMain('stop_streaming');
    }
  }
}
