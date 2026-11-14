import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../logic/jetlag_clock.dart';
import 'jetlag_alert_channel.dart';

/// Schedules only on [JetlagAlertChannel]. Callers cannot pick another channel.
abstract class JetlagAlertScheduler {
  Future<bool> ensureChannel();
  Future<bool> requestPermission();
  Future<void> schedulePickupReminder({
    required int id,
    required DateTime whenUtc,
    required String title,
    required String body,
  });
  Future<void> cancel({required int id});
}

class JetlagLocalAlertScheduler implements JetlagAlertScheduler {
  JetlagLocalAlertScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  @override
  Future<bool> ensureChannel() async {
    try {
      if (!_ready) {
        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
            ),
          ),
        );
        _ready = true;
      }
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        JetlagAlertChannel.androidChannel,
      );
      return true;
    } catch (error, stack) {
      debugPrint('jetlag channel setup failed: $error\n$stack');
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final androidOk = await android?.requestNotificationsPermission();
      final iosOk = await ios?.requestPermissions(alert: true, sound: true);
      if (androidOk == false && iosOk != true) return false;
      if (iosOk == false && androidOk != true) return false;
      return true;
    } catch (error, stack) {
      debugPrint('jetlag notification permission failed: $error\n$stack');
      return false;
    }
  }

  @override
  Future<void> schedulePickupReminder({
    required int id,
    required DateTime whenUtc,
    required String title,
    required String body,
  }) async {
    assert(
      id >= JetlagAlertChannel.idRangeStart &&
          id <= JetlagAlertChannel.idRangeEnd,
    );
    ensureJetlagTimeZones();
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(whenUtc.toUtc(), tz.UTC),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: JetlagAlertChannel.notificationDetails,
    );
  }

  @override
  Future<void> cancel({required int id}) {
    return _plugin.cancel(id: id);
  }
}
