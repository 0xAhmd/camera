import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

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
          ),
        ],
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<bool> start({
    required String ip,
    required int port,
  }) async {
    await init();

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'PhoneCam Active',
        notificationText: 'Streaming to $ip:$port',
      );

      return true;
    }

    return await FlutterForegroundTask.startService(
      notificationTitle: 'PhoneCam Active',
      notificationText: 'Streaming camera to PC...',
      callback: startCallback,
    );
  }

  static Future<bool> stop() async {
    return await FlutterForegroundTask.stopService();
  }

  static Future<bool> isRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(
    _ForegroundTaskHandler(),
  );
}

class _ForegroundTaskHandler extends TaskHandler {
  int _heartbeat = 0;

  @override
  Future<void> onStart(
    DateTime timestamp,
    SendPort? sendPort,
  ) async {
    debugPrint('Foreground task started');
  }

  @override
  void onRepeatEvent(
    DateTime timestamp,
    SendPort? sendPort,
  ) {
    _heartbeat++;

    FlutterForegroundTask.updateService(
      notificationText: 'Streaming active · ${_heartbeat * 5}s',
    );

    sendPort?.send(_heartbeat);
  }

  @override
  Future<void> onDestroy(
    DateTime timestamp,
    SendPort? sendPort,
  ) async {
    debugPrint('Foreground task destroyed');
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      debugPrint('Stop button pressed');
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  void onReceiveData(Object data) {
    debugPrint('Received data: $data');
  }
}