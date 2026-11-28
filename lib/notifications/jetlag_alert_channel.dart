import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Roster background alerts must not reuse this channel or this id range.
class JetlagAlertChannel {
  const JetlagAlertChannel._();

  static const id = 'jetlag_guide_alerts';
  static const name = '시차·컨디션 알림';
  static const description =
      '카페인 마감, 식사, 취침 안내. 로스터 알림과 분리됩니다.';

  /// Legacy pickup switch key — no longer read to enable alerts.
  static const enabledKey = 'jetlag_guide_alerts_enabled';

  /// Legacy pickup notification id — cancel only, do not reschedule.
  static const pickupNotificationId = 71001;
  static const idRangeStart = 71000;
  static const idRangeEnd = 71999;

  /// Legacy wake channel / ids — cancel only, do not reschedule.
  static const wakeChannelId = 'jetlag_guide_wake';
  static const wakeEnabledKey = 'jetlag_guide_wake_alerts_enabled';
  static const wakeIdStart = 71100;
  static const wakeMaxCount = 12;

  static const testNotificationId = 71199;

  static const caffeineEnabledKey = 'jetlag_guide_caffeine_alerts_enabled';
  static const mealEnabledKey = 'jetlag_guide_meal_alerts_enabled';
  static const bedEnabledKey = 'jetlag_guide_bed_alerts_enabled';
  static const caffeineIdStart = 71200;
  static const mealIdStart = 71300;
  static const bedIdStart = 71400;
  static const guideMaxCount = 12;

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
