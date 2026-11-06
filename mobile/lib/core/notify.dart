// Alarms as phone notifications (Android, iOS): a sensor that trips while the app is running -
// open or in the background - shows in the phone's notification shade with sound and vibration.
// The permission is asked once after sign-in. The browser version has none (the red bar and the
// SMS to the home's contacts remain).

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class Notify {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static bool get supported => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> init() async {
    if (!supported || _ready) return;
    try {
      await _plugin.initialize(settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestSoundPermission: false,
            requestBadgePermission: false),
      ));
      _ready = true;
    } catch (e) {
      debugPrint('notifications unavailable: $e');
    }
  }

  /// Ask for permission to show notifications (Android 13+, iOS); true when allowed.
  static Future<bool> ask() async {
    if (!supported) return false;
    await init();
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, sound: true, badge: true) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// One alarm (the same id replaces itself: another trip of the same alert).
  static Future<void> alarm(int id, String title, String body,
      {required String channel, required String channelHelp}) async {
    if (!supported) return;
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails('security_alarms', channel,
              channelDescription: channelHelp,
              importance: Importance.max,
              priority: Priority.high,
              category: AndroidNotificationCategory.alarm,
              color: const Color(0xFFFF4D5E),
              ticker: title),
          iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true,
              interruptionLevel: InterruptionLevel.timeSensitive),
        ),
      );
    } catch (e) {
      debugPrint('notification not shown: $e');
    }
  }
}
