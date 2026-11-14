import '../models/guide_event.dart';
import '../models/jetlag_schedule.dart';
import '../models/lifestyle.dart';
import 'jetlag_clock.dart';

class _SleepWindow {
  const _SleepWindow({required this.startUtc, required this.endUtc});

  final DateTime startUtc;
  final DateTime endUtc;
}

/// Sleep, caffeine, meal, and light blocks for the selected lifestyle.
/// Arrival, pickup, and departure stay on the injected schedule.
List<GuideEvent> lifestyleBlocks({
  required JetlagScheduleSnapshot schedule,
  required JetlagLifestyle lifestyle,
}) {
  final sta = schedule.staUtc.toUtc();
  final std = schedule.stdUtc.toUtc();
  if (!std.isAfter(sta)) return const [];

  final windows = _sleepWindows(schedule, lifestyle);
  final sleeps = windows.isEmpty ? [_fallbackSleep(schedule)] : windows;
  final blocks = <GuideEvent>[];
  for (final sleep in sleeps) {
    final caffeine = sleep.startUtc.subtract(const Duration(hours: 6));
    if (!caffeine.isBefore(sta) && caffeine.isBefore(sleep.startUtc)) {
      blocks.add(
        GuideEvent(
          id: 'caffeine-${caffeine.microsecondsSinceEpoch}',
          kind: GuideEventKind.caffeine,
          startUtc: caffeine,
          title: '카페인 마감',
          detail: '이 시각 이후 카페인을 피합니다.',
        ),
      );
    }
    final dinner = sleep.startUtc.subtract(const Duration(hours: 3));
    if (!dinner.isBefore(sta) && dinner.isBefore(sleep.startUtc)) {
      blocks.add(
        GuideEvent(
          id: 'meal-${dinner.microsecondsSinceEpoch}',
          kind: GuideEventKind.meal,
          startUtc: dinner,
          title: '식사',
          detail: '잠들기 전 식사.',
        ),
      );
    }
    blocks.add(
      GuideEvent(
        id: 'sleep-${sleep.startUtc.microsecondsSinceEpoch}',
        kind: GuideEventKind.sleep,
        startUtc: sleep.startUtc,
        endUtc: sleep.endUtc,
        title: '수면',
        detail: lifestyle.sleepDetailFor(schedule.referenceTimeZone),
      ),
    );
    final lightEnd = sleep.endUtc.add(const Duration(minutes: 30));
    if (sleep.endUtc.isBefore(std) && sleep.endUtc.isAfter(sta)) {
      blocks.add(
        GuideEvent(
          id: 'light-${sleep.endUtc.microsecondsSinceEpoch}',
          kind: GuideEventKind.light,
          startUtc: sleep.endUtc,
          endUtc: lightEnd.isAfter(std) ? std : lightEnd,
          title: '빛 노출',
          detail: '기상 후 밝은 빛을 봅니다.',
        ),
      );
    }
  }
  return blocks;
}

List<_SleepWindow> _sleepWindows(
  JetlagScheduleSnapshot schedule,
  JetlagLifestyle lifestyle,
) {
  final sta = schedule.staUtc.toUtc();
  final std = schedule.stdUtc.toUtc();
  final zone = lifestyle == JetlagLifestyle.localAdapt
      ? schedule.localTimeZone
      : schedule.referenceTimeZone;
  final shift = lifestyle == JetlagLifestyle.hybrid
      ? _hybridShift(
          zoneOffset(sta, schedule.localTimeZone, schedule.referenceTimeZone),
        )
      : Duration.zero;
  final pickup = schedule.pickupUtc?.toUtc();
  final windows = <_SleepWindow>[];
  for (final day in calendarDays(zone, sta, std)) {
    final bed = zonedUtc(
      iana: zone,
      year: day.year,
      month: day.month,
      day: day.day,
      hour: JetlagLifestyle.bedMinute ~/ 60,
      minute: JetlagLifestyle.bedMinute % 60,
      shift: shift,
    );
    var wake = zonedUtc(
      iana: zone,
      year: day.year,
      month: day.month,
      day: day.day,
      hour: JetlagLifestyle.wakeMinute ~/ 60,
      minute: JetlagLifestyle.wakeMinute % 60,
      shift: shift,
    );
    if (!wake.isAfter(bed)) {
      final next = DateTime(day.year, day.month, day.day + 1);
      wake = zonedUtc(
        iana: zone,
        year: next.year,
        month: next.month,
        day: next.day,
        hour: JetlagLifestyle.wakeMinute ~/ 60,
        minute: JetlagLifestyle.wakeMinute % 60,
        shift: shift,
      );
    }
    final end = _pulledWake(wake, pickup);
    if (!end.isAfter(bed)) continue;
    if (!bed.isBefore(std) || !end.isAfter(sta)) continue;
    windows.add(_SleepWindow(startUtc: bed, endUtc: end));
  }
  return windows;
}

DateTime _pulledWake(DateTime wakeUtc, DateTime? pickupUtc) {
  if (pickupUtc == null) return wakeUtc;
  final ready = pickupUtc.subtract(const Duration(minutes: 90));
  return ready.isBefore(wakeUtc) ? ready : wakeUtc;
}

/// Shorter way around the clock, then capped at ±2 hours.
Duration _hybridShift(Duration zoneOffset) {
  var minutes = -zoneOffset.inMinutes;
  const day = 24 * 60;
  const half = 12 * 60;
  while (minutes > half) {
    minutes -= day;
  }
  while (minutes <= -half) {
    minutes += day;
  }
  final cap = JetlagLifestyle.hybridCap.inMinutes;
  if (minutes > cap) minutes = cap;
  if (minutes < -cap) minutes = -cap;
  return Duration(minutes: minutes);
}

_SleepWindow _fallbackSleep(JetlagScheduleSnapshot schedule) {
  final sta = schedule.staUtc.toUtc();
  final std = schedule.stdUtc.toUtc();
  final pickup = schedule.pickupUtc?.toUtc();
  final anchor = pickup ?? std.subtract(const Duration(hours: 3));
  var sleepStart = sta.add(const Duration(hours: 8));
  var sleepEnd = sleepStart.add(const Duration(hours: 8));
  final latestWake = anchor.subtract(const Duration(hours: 3));
  if (sleepEnd.isAfter(latestWake)) sleepEnd = latestWake;
  if (sleepEnd.difference(sleepStart) < const Duration(hours: 3)) {
    sleepEnd = latestWake.isBefore(std)
        ? latestWake
        : std.subtract(const Duration(hours: 2));
    sleepStart = sleepEnd.subtract(const Duration(hours: 3));
  }
  if (sleepStart.isBefore(sta.add(const Duration(hours: 1)))) {
    sleepStart = sta.add(const Duration(hours: 1));
  }
  if (!sleepEnd.isAfter(sleepStart)) {
    sleepEnd = sleepStart.add(const Duration(hours: 1));
  }
  return _SleepWindow(startUtc: sleepStart, endUtc: sleepEnd);
}
