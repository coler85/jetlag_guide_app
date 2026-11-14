import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Roster background alerts must not reuse this channel or this id range.
class JetlagAlertChannel {
  const JetlagAlertChannel._();

  static const id = 'jetlag_guide_alerts';
  static const name = '시차·컨디션 알림';
  static const description = '픽업, 기상, 카페인 컷오프 등 시차 가이드 알림. 로스터 알림과 분리됩니다.';
  static const enabledKey = 'jetlag_guide_alerts_enabled';
  static const pickupNotificationId = 71001;
  static const idRangeStart = 71000;
  static const idRangeEnd = 71999;
  static const pickupLead = Duration(minutes: 90);

  static const androidChannel = AndroidNotificationChannel(
    id,
    name,
    description: description,
    importance: Importance.high,
  );

  static const notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      id,
      name,
      channelDescription: description,
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      threadIdentifier: id,
      categoryIdentifier: id,
    ),
  );
}
