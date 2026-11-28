import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../logic/jetlag_clock.dart';
import 'jetlag_alert_channel.dart';

/// Schedules only on [JetlagAlertChannel]. Callers cannot pick another channel.
abstract class JetlagAlertScheduler {
  Future<bool> ensureChannel();
  Future<bool> requestPermission();
  Future<void> scheduleAlert({
    required int id,
    required DateTime whenUtc,
    required String title,
    required String body,
  });
  Future<void> cancel({required int id});
  Future<void> cancelRange({required int start, required int count});
  Future<bool> canScheduleExact();
  Future<void> requestExactAlarm();
  Future<void> scheduleTestAlert({
    required DateTime whenUtc,
    required String localIana,
    required String homeIana,
  });
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
  Future<void> scheduleAlert({
    required int id,
    required DateTime whenUtc,
    required String title,
    required String body,
  }) async {
    assert(
      id >= JetlagAlertChannel.idRangeStart &&
          id <= JetlagAlertChannel.idRangeEnd,
    );
    try {
      ensureJetlagTimeZones();
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(whenUtc.toUtc(), tz.UTC),
        androidScheduleMode: await _androidScheduleMode(),
        notificationDetails: JetlagAlertChannel.notificationDetails,
      );
    } catch (error, stack) {
      debugPrint('jetlag alert schedule failed: $error\n$stack');
    }
  }

  @override
  Future<void> cancel({required int id}) {
    return _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelRange({required int start, required int count}) async {
    try {
      for (var i = 0; i < count; i++) {
        await _plugin.cancel(id: start + i);
      }
    } catch (error, stack) {
      debugPrint('jetlag alert cancel range failed: $error\n$stack');
    }
  }

  @override
  Future<bool> canScheduleExact() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return true;
      return await android.canScheduleExactNotifications() ?? false;
    } catch (error, stack) {
      debugPrint('jetlag exact alarm check failed: $error\n$stack');
      return false;
    }
  }

  @override
  Future<void> requestExactAlarm() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestExactAlarmsPermission();
    } catch (error, stack) {
      debugPrint('jetlag exact alarm request failed: $error\n$stack');
    }
  }

  @override
  Future<void> scheduleTestAlert({
    required DateTime whenUtc,
    required String localIana,
    required String homeIana,
  }) async {
    try {
      ensureJetlagTimeZones();
      final when = whenUtc.toUtc();
      await _plugin.zonedSchedule(
        id: JetlagAlertChannel.testNotificationId,
        title:
            '테스트 ${formatHm(when, localIana)} · '
            '홈 ${formatHm(when, homeIana)} '
            '${zoneAbbreviation(when, homeIana)}',
        body: '이 알림이 워치에도 보이면 연동이 된 거예요.',
        scheduledDate: tz.TZDateTime.from(when, tz.UTC),
        androidScheduleMode: await _androidScheduleMode(),
        notificationDetails: JetlagAlertChannel.notificationDetails,
      );
    } catch (error, stack) {
      debugPrint('jetlag test alert failed: $error\n$stack');
    }
  }

  Future<AndroidScheduleMode> _androidScheduleMode() async {
    final exact = await canScheduleExact();
    return exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }
}
