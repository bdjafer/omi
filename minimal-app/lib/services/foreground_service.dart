import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class ForegroundServiceManager {
  static final ForegroundServiceManager _instance = ForegroundServiceManager._internal();
  factory ForegroundServiceManager() => _instance;
  ForegroundServiceManager._internal();

  Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'omi_audio_streaming',
        channelName: 'OMI Audio Streaming',
        channelDescription: 'Streaming audio from OMI device',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
        playSound: false,
        enableVibration: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<bool> start() async {
    if (await FlutterForegroundTask.isRunningService) return true;
    await FlutterForegroundTask.startService(
      notificationTitle: 'OMI Streaming',
      notificationText: 'Audio streaming active',
      callback: startCallback,
    );
    return true;
  }

  Future<bool> stop() async {
    await FlutterForegroundTask.stopService();
    return true;
  }

  Future<void> updateNotification(String text) async {
    await FlutterForegroundTask.updateService(notificationText: text);
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(OmiTaskHandler());
}

class OmiTaskHandler extends TaskHandler {
  int _eventCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('ForegroundTask: onStart');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _eventCount++;
    FlutterForegroundTask.updateService(notificationText: 'Streaming... ($_eventCount)');
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    print('ForegroundTask: onDestroy');
  }

  @override
  void onNotificationButtonPressed(String id) {
    print('ForegroundTask: Button pressed $id');
  }

  @override
  void onNotificationPressed() {
    print('ForegroundTask: Notification pressed');
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {
    print('ForegroundTask: Notification dismissed');
  }
}
