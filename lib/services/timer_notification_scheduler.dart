import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../l10n/app_strings.dart';

/// iOS `TimerNotificationScheduler` に対応
class TimerNotificationScheduler {
  TimerNotificationScheduler._();

  static final TimerNotificationScheduler instance =
      TimerNotificationScheduler._();

  static const _notificationId = 1;
  static const _channelId = 'osm_washabe_timer';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _channelLanguageCode;

  Future<void> initialize({String languageCode = 'ja'}) async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestAlertPermission: true,
    );
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings: settings);

    if (Platform.isAndroid) {
      await _ensureAndroidChannel(languageCode);
    }

    await requestAuthorization();
    _initialized = true;
  }

  Future<void> _ensureAndroidChannel(String languageCode) async {
    if (!Platform.isAndroid) return;
    if (_channelLanguageCode == languageCode) return;
    _channelLanguageCode = languageCode;

    final androidChannel = AndroidNotificationChannel(
      _channelId,
      'タイマー'.tr(languageCode),
      description: 'タイマー終了通知'.tr(languageCode),
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> requestAuthorization() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> schedule(
    int seconds, {
    required String languageCode,
  }) async {
    if (!_initialized || seconds <= 0) return;
    await cancel();

    if (Platform.isAndroid) {
      await _ensureAndroidChannel(languageCode);
    }

    final body = 'タイマー終了通知'.tr(languageCode);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'タイマー'.tr(languageCode),
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final scheduled = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));
    await _plugin.zonedSchedule(
      id: _notificationId,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancel() async {
    if (!_initialized) return;
    await _plugin.cancel(id: _notificationId);
  }
}
