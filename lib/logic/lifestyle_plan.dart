import '../models/guide_event.dart';
import '../models/jetlag_schedule.dart';
import '../models/lifestyle.dart';
import '../models/user_settings.dart';
import 'home_departure.dart';
import 'hybrid_strategy.dart';
import 'jetlag_clock.dart';

class _SleepWindow {
  const _SleepWindow({
    required this.startUtc,
    required this.endUtc,
    this.earlyShowUp = false,
  });

  final DateTime startUtc;
  final DateTime endUtc;
  final bool earlyShowUp;
}

/// Sleep, caffeine, meal, and light blocks for the selected lifestyle.
/// Arrival, pickup, and departure stay on the injected schedule.
List<GuideEvent> lifestyleBlocks({
  required JetlagScheduleSnapshot schedule,
  required JetlagLifestyle lifestyle,
  UserSettings settings = UserSettings.defaults,
}) {
  final sta = schedule.staUtc.toUtc();
  final std = schedule.stdUtc.toUtc();
  if (!std.isAfter(sta)) return const [];

  final windows = _sleepWindows(schedule, lifestyle, settings);
  final sleeps = windows.isEmpty
      ? [_fallbackSleep(schedule, settings.sleepTarget)]
      : windows;
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
        detail: sleep.earlyShowUp
            ? '새벽 쇼업에 맞춰 미리 잡니다. 알람 기상 ${formatHm(sleep.endUtc, schedule.referenceTimeZone)}.'
            : lifestyle.sleepDetailFor(
                schedule.referenceTimeZone,
                hybridMaxShiftHours: settings.hybridMaxShiftHours,
              ),
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
  UserSettings settings,
) {
  final sta = schedule.staUtc.toUtc();
  final std = schedule.stdUtc.toUtc();
  final zone = lifestyle == JetlagLifestyle.localAdapt
      ? schedule.localTimeZone
      : schedule.referenceTimeZone;
  final shift = lifestyle == JetlagLifestyle.hybrid
      ? const HybridStrategy().shift(
          zoneOffset: zoneOffset(
            sta,
            schedule.localTimeZone,
            schedule.referenceTimeZone,
          ),
          maxShift: Duration(hours: settings.hybridMaxShiftHours),
        )
      : Duration.zero;
  final bedMinute = settings.defaultBedTime.minuteOfDay;
  final wakeMinute = settings.defaultWakeTime.minuteOfDay;
  final pickup = schedule.pickupUtc?.toUtc();
  final windows = <_SleepWindow>[];
  for (final day in calendarDays(zone, sta, std)) {
    final bed = zonedUtc(
      iana: zone,
      year: day.year,
      month: day.month,
      day: day.day,
      hour: bedMinute ~/ 60,
      minute: bedMinute % 60,
      shift: shift,
    );
    var wake = zonedUtc(
      iana: zone,
      year: day.year,
      month: day.month,
      day: day.day,
      hour: wakeMinute ~/ 60,
      minute: wakeMinute % 60,
      shift: shift,
    );
    if (!wake.isAfter(bed)) {
      final next = DateTime(day.year, day.month, day.day + 1);
      wake = zonedUtc(
        iana: zone,
        year: next.year,
        month: next.month,
        day: next.day,
        hour: wakeMinute ~/ 60,
        minute: wakeMinute % 60,
        shift: shift,
      );
    }
    final end = _pulledWake(wake, pickup);
    if (!end.isAfter(bed)) continue;
    if (!bed.isBefore(std) || !end.isAfter(sta)) continue;
    windows.add(_SleepWindow(startUtc: bed, endUtc: end));
  }
  return _withHomeDeparture(schedule, settings, windows);
}

/// Replaces the usual night that a dawn report cuts, with the earlier window.
List<_SleepWindow> _withHomeDeparture(
  JetlagScheduleSnapshot schedule,
  UserSettings settings,
  List<_SleepWindow> windows,
) {
  final plan = const HomeDepartureAdvisor().evaluate(
    schedule: schedule,
    settings: settings,
  );
  final start = plan.recommendedStartUtc;
  final end = plan.recommendedEndUtc;
  final naturalBed = plan.naturalBedUtc;
  final naturalWake = plan.naturalWakeUtc;
  if (!plan.applies ||
      start == null ||
      end == null ||
      naturalBed == null ||
      naturalWake == null ||
      !end.isAfter(start)) {
    return windows;
  }
  final sta = schedule.staUtc.toUtc();
  final std = schedule.stdUtc.toUtc();
  if (!start.isBefore(std) || !end.isAfter(sta)) return windows;

  final kept = windows.where((window) {
    final hitsNight = _rangesOverlap(
      window.startUtc,
      window.endUtc,
      naturalBed,
      naturalWake,
    );
    final hitsPlan = _rangesOverlap(window.startUtc, window.endUtc, start, end);
    return !hitsNight && !hitsPlan;
  }).toList();
  kept.add(_SleepWindow(startUtc: start, endUtc: end, earlyShowUp: true));
  kept.sort((a, b) => a.startUtc.compareTo(b.startUtc));
  return kept;
}

bool _rangesOverlap(DateTime a0, DateTime a1, DateTime b0, DateTime b1) {
  return a0.isBefore(b1) && b0.isBefore(a1);
}

DateTime _pulledWake(DateTime wakeUtc, DateTime? pickupUtc) {
  if (pickupUtc == null) return wakeUtc;
  final ready = pickupUtc.subtract(const Duration(minutes: 90));
  return ready.isBefore(wakeUtc) ? ready : wakeUtc;
}

_SleepWindow _fallbackSleep(JetlagScheduleSnapshot schedule, Duration target) {
  final sta = schedule.staUtc.toUtc();
  final std = schedule.stdUtc.toUtc();
  final pickup = schedule.pickupUtc?.toUtc();
  final anchor = pickup ?? std.subtract(const Duration(hours: 3));
  final span = target > Duration.zero
      ? target
      : UserSettings.defaults.sleepTarget;
  var sleepStart = sta.add(span);
  var sleepEnd = sleepStart.add(span);
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
