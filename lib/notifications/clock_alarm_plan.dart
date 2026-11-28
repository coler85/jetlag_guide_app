import '../models/guide_event.dart';

/// Wall time on the device clock for [whenUtc].
///
/// Planner instants are often `TZDateTime`s. `TZDateTime.toLocal()` uses
/// `tz.local`, which stays at UTC after `initializeTimeZones` because this
/// app never calls `setLocalLocation`. That would register UTC hours into
/// the phone clock — one hour early for Europe/Amsterdam in winter (CET).
/// Convert to a native UTC [DateTime] first so [DateTime.toLocal] uses the
/// OS timezone (KST when the phone is in Korea).
DateTime clockAlarmDeviceLocal(DateTime whenUtc) {
  final utc = whenUtc.toUtc();
  return DateTime.fromMicrosecondsSinceEpoch(
    utc.microsecondsSinceEpoch,
    isUtc: true,
  ).toLocal();
}

const kClockAlarmWakeMessage = '기상';
const kClockAlarmWakeupCallMessage = '웨이크업콜';
const kClockAlarmWindow = Duration(hours: 24);

class ClockAlarmPlan {
  const ClockAlarmPlan({
    required this.whenUtc,
    required this.message,
    required this.active,
  });

  final DateTime whenUtc;
  final String message;

  /// True when [whenUtc] is after now and at or before now+24h.
  final bool active;

  @override
  bool operator ==(Object other) {
    return other is ClockAlarmPlan &&
        other.whenUtc.isAtSameMomentAs(whenUtc) &&
        other.message == message &&
        other.active == active;
  }

  @override
  int get hashCode =>
      Object.hash(whenUtc.millisecondsSinceEpoch, message, active);
}

/// True when [whenUtc] is after [nowUtc] and at or before now+24h.
bool isClockAlarmWithinWindow(DateTime whenUtc, DateTime nowUtc) {
  final when = whenUtc.toUtc();
  final now = nowUtc.toUtc();
  if (!when.isAfter(now)) return false;
  final deadline = now.add(kClockAlarmWindow);
  return when.isBefore(deadline) || when.isAtSameMomentAs(deadline);
}

/// Soonest planned sleep end after [nowUtc], excluding logged/inflight rest.
ClockAlarmPlan? planNextClockWake({
  required List<GuideEvent> events,
  required DateTime nowUtc,
}) {
  final now = nowUtc.toUtc();
  DateTime? soonest;
  for (final event in events) {
    if (event.kind != GuideEventKind.sleep) continue;
    final end = event.endUtc?.toUtc();
    if (end == null || !end.isAfter(now)) continue;
    if (soonest == null || end.isBefore(soonest)) soonest = end;
  }
  if (soonest == null) return null;
  return ClockAlarmPlan(
    whenUtc: soonest,
    message: kClockAlarmWakeMessage,
    active: isClockAlarmWithinWindow(soonest, now),
  );
}

/// Pickup minus one hour when that instant is still in the future.
ClockAlarmPlan? planNextWakeupCall({
  required DateTime? pickupUtc,
  required DateTime nowUtc,
}) {
  final pickup = pickupUtc?.toUtc();
  if (pickup == null) return null;
  final now = nowUtc.toUtc();
  final when = pickup.subtract(const Duration(hours: 1));
  if (!when.isAfter(now)) return null;
  return ClockAlarmPlan(
    whenUtc: when,
    message: kClockAlarmWakeupCallMessage,
    active: isClockAlarmWithinWindow(when, now),
  );
}
