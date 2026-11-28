import '../logic/jetlag_clock.dart';
import '../models/guide_event.dart';
import 'jetlag_alert_channel.dart';

class GuideAlert {
  const GuideAlert({
    required this.id,
    required this.whenUtc,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime whenUtc;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) {
    return other is GuideAlert &&
        other.id == id &&
        other.whenUtc.isAtSameMomentAs(whenUtc) &&
        other.title == title &&
        other.body == body;
  }

  @override
  int get hashCode =>
      Object.hash(id, whenUtc.millisecondsSinceEpoch, title, body);
}

/// Caffeine cutoffs at [GuideEventKind.caffeine] start, soonest first.
List<GuideAlert> planCaffeineAlerts({
  required List<GuideEvent> events,
  required DateTime nowUtc,
  required String localIana,
  required String homeIana,
  int max = JetlagAlertChannel.guideMaxCount,
}) {
  return _planAtStart(
    events: events,
    kind: GuideEventKind.caffeine,
    nowUtc: nowUtc,
    localIana: localIana,
    homeIana: homeIana,
    idStart: JetlagAlertChannel.caffeineIdStart,
    max: max,
    titlePrefix: '카페인 마감',
    body: '카페인 마감 시각이에요',
  );
}

/// Meals at [GuideEventKind.meal] start only (not mealDeadline).
List<GuideAlert> planMealAlerts({
  required List<GuideEvent> events,
  required DateTime nowUtc,
  required String localIana,
  required String homeIana,
  int max = JetlagAlertChannel.guideMaxCount,
}) {
  return _planAtStart(
    events: events,
    kind: GuideEventKind.meal,
    nowUtc: nowUtc,
    localIana: localIana,
    homeIana: homeIana,
    idStart: JetlagAlertChannel.mealIdStart,
    max: max,
    titlePrefix: '식사',
    body: '식사 시간이에요',
  );
}

/// Planned sleep bedtime reminders: fire 30 minutes before sleep start.
/// Title times are the bedtime (sleep start), not the fire time.
List<GuideAlert> planBedAlerts({
  required List<GuideEvent> events,
  required DateTime nowUtc,
  required String localIana,
  required String homeIana,
  int max = JetlagAlertChannel.guideMaxCount,
}) {
  final now = nowUtc.toUtc();
  final beds = <DateTime>[];
  for (final event in events) {
    if (event.kind != GuideEventKind.sleep) continue;
    final bed = event.startUtc.toUtc();
    final fireAt = bed.subtract(const Duration(minutes: 30));
    if (!fireAt.isAfter(now)) continue;
    beds.add(bed);
  }
  beds.sort((a, b) => a.compareTo(b));
  final limited = beds.take(max).toList();
  return [
    for (var i = 0; i < limited.length; i++)
      GuideAlert(
        id: JetlagAlertChannel.bedIdStart + i,
        whenUtc: limited[i].subtract(const Duration(minutes: 30)),
        title: _dualZoneTitle('곧 취침', limited[i], localIana, homeIana),
        body: '곧 취침이에요',
      ),
  ];
}

String guideAlertSignature(List<GuideAlert> alerts) {
  if (alerts.isEmpty) return '';
  return alerts
      .map(
        (alert) =>
            '${alert.id}|${alert.whenUtc.toUtc().toIso8601String()}|'
            '${alert.title}|${alert.body}',
      )
      .join('\n');
}

List<GuideAlert> _planAtStart({
  required List<GuideEvent> events,
  required GuideEventKind kind,
  required DateTime nowUtc,
  required String localIana,
  required String homeIana,
  required int idStart,
  required int max,
  required String titlePrefix,
  required String body,
}) {
  final now = nowUtc.toUtc();
  final starts = <DateTime>[];
  for (final event in events) {
    if (event.kind != kind) continue;
    final start = event.startUtc.toUtc();
    if (!start.isAfter(now)) continue;
    starts.add(start);
  }
  starts.sort((a, b) => a.compareTo(b));
  final limited = starts.take(max).toList();
  return [
    for (var i = 0; i < limited.length; i++)
      GuideAlert(
        id: idStart + i,
        whenUtc: limited[i],
        title: _dualZoneTitle(titlePrefix, limited[i], localIana, homeIana),
        body: body,
      ),
  ];
}

String _dualZoneTitle(
  String prefix,
  DateTime whenUtc,
  String localIana,
  String homeIana,
) {
  final when = whenUtc.toUtc();
  return '$prefix ${formatHm(when, localIana)} · '
      '홈 ${formatHm(when, homeIana)} '
      '${zoneAbbreviation(when, homeIana)}';
}
