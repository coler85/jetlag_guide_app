import '../models/guide_event.dart';
import '../models/jetlag_schedule.dart';
import '../models/lifestyle.dart';
import '../models/user_settings.dart';
import 'home_departure.dart';
import 'hybrid_strategy.dart';
import 'jetlag_clock.dart';
import 'sleep_constants.dart';

class _SleepWindow {
  const _SleepWindow({
    required this.startUtc,
    required this.endUtc,
    this.earlyShowUp = false,
    this.detail,
  });

  final DateTime startUtc;
  final DateTime endUtc;
  final bool earlyShowUp;
  final String? detail;
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
  final sleeps = _mergeCloseSleeps(
    _withPreDepartureSleep(
      schedule,
      settings,
      lifestyle,
      windows.isEmpty
          ? _firstSleepAfterArrival(schedule, lifestyle, settings)
          : windows,
    ),
    floor: sta.add(settings.arrivalToSleep),
    target: settings.sleepTarget,
    std: std,
  );
  final blocks = <GuideEvent>[];
  for (var index = 0; index < sleeps.length; index++) {
    final sleep = sleeps[index];
    final next = index + 1 < sleeps.length ? sleeps[index + 1] : null;
    final caffeine = sleep.startUtc.subtract(const Duration(hours: 6));
    if (!caffeine.isBefore(sta) &&
        caffeine.isBefore(sleep.startUtc) &&
        !_insideSleep(caffeine, sleeps)) {
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
    final dinner = sleep.startUtc.subtract(kMealLead);
    if (!dinner.isBefore(sta) &&
        dinner.isBefore(sleep.startUtc) &&
        !_insideSleep(dinner, sleeps)) {
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
        detail:
            sleep.detail ??
            (sleep.earlyShowUp
                ? '${_preDepartureDetail(schedule)} '
                      '알람 기상 ${formatHm(sleep.endUtc, schedule.referenceTimeZone)}.'
                : lifestyle.sleepDetailFor(
                    schedule.referenceTimeZone,
                    hybridMaxShiftHours: settings.hybridMaxShiftHours,
                  )),
      ),
    );
    final light = _lightAfterSleep(sleep, next, sta, std);
    if (light != null) blocks.add(light);
  }
  return blocks;
}

/// Light only after sleep. A block that would fall in the two hours before
/// the next sleep is cut off, and dropped when nothing remains.
GuideEvent? _lightAfterSleep(
  _SleepWindow sleep,
  _SleepWindow? next,
  DateTime sta,
  DateTime std,
) {
  if (!sleep.endUtc.isBefore(std) || !sleep.endUtc.isAfter(sta)) return null;
  var lightEnd = sleep.endUtc.add(const Duration(minutes: 30));
  if (next != null) {
    final quiet = next.startUtc.subtract(kMealLead);
    if (lightEnd.isAfter(quiet)) lightEnd = quiet;
  }
  if (lightEnd.isAfter(std)) lightEnd = std;
  if (!lightEnd.isAfter(sleep.endUtc)) return null;
  return GuideEvent(
    id: 'light-${sleep.endUtc.microsecondsSinceEpoch}',
    kind: GuideEventKind.light,
    startUtc: sleep.endUtc,
    endUtc: lightEnd,
    title: '빛 노출',
    detail: '기상 후 밝은 빛을 봅니다.',
  );
}

bool _insideSleep(DateTime instant, List<_SleepWindow> sleeps) {
  return sleeps.any(
    (sleep) =>
        !instant.isBefore(sleep.startUtc) && instant.isBefore(sleep.endUtc),
  );
}

/// Last sleep before departure, only when the pickup (or, with no pickup,
/// departure minus the show-up lead) falls in that mode's night.
///
/// The wake is still pickup − prep − commute when a 90-minute cycle fits,
/// otherwise departure − show-up lead − prep − commute. A window that
/// already ends at this wake is left as it is. A mode night that overlaps
/// the new block keeps a prefix of at least one cycle. [_mergeCloseSleeps]
/// then joins any pair whose gap is under [kSleepMergeGap].
List<_SleepWindow> _withPreDepartureSleep(
  JetlagScheduleSnapshot schedule,
  UserSettings settings,
  JetlagLifestyle lifestyle,
  List<_SleepWindow> windows,
) {
  final anchor = _departureAnchor(schedule, settings);
  if (anchor == null ||
      !_inModeNight(anchor, _modeClock(schedule, lifestyle, settings))) {
    return windows;
  }
  final sta = schedule.staUtc.toUtc();
  final std = schedule.stdUtc.toUtc();
  final wake = const HomeDepartureAdvisor().preDepartureWake(
    schedule: schedule,
    settings: settings,
  );
  if (wake == null || !wake.isBefore(std) || !wake.isAfter(sta)) {
    return windows;
  }
  if (windows.any((window) => window.endUtc == wake)) return windows;
  final block = _cyclesEndingAt(
    wake: wake,
    earliest: sta.add(settings.arrivalToSleep),
    target: settings.sleepTarget,
    std: std,
  );
  if (block == null) return windows;
  final departure = _SleepWindow(
    startUtc: block.startUtc,
    endUtc: block.endUtc,
    detail: _preDepartureDetail(schedule),
  );
  final kept = <_SleepWindow>[];
  for (final window in windows) {
    if (!_rangesOverlap(
      window.startUtc,
      window.endUtc,
      departure.startUtc,
      departure.endUtc,
    )) {
      kept.add(window);
      continue;
    }
    if (!window.startUtc.isBefore(departure.startUtc)) continue;
    final prefix = _cyclesEndingAt(
      wake: departure.startUtc,
      earliest: window.startUtc,
      target: settings.sleepTarget,
      std: std,
    );
    if (prefix != null) kept.add(prefix);
  }
  kept.add(departure);
  kept.sort((a, b) => a.startUtc.compareTo(b.startUtc));
  return kept;
}

/// Joins neighbors whose gap is under [kSleepMergeGap]. The end stays on the
/// later wake. The length is the longest run of 90-minute cycles inside
/// [target]. A gap of [kSleepMergeGap] or more is left as two blocks.
List<_SleepWindow> _mergeCloseSleeps(
  List<_SleepWindow> sleeps, {
  required DateTime floor,
  required Duration target,
  required DateTime std,
}) {
  if (sleeps.length < 2) return sleeps;
  final sorted = [...sleeps]..sort((a, b) => a.startUtc.compareTo(b.startUtc));
  final merged = <_SleepWindow>[sorted.first];
  for (final next in sorted.skip(1)) {
    final previous = merged.last;
    final gap = next.startUtc.difference(previous.endUtc);
    if (gap < kSleepMergeGap) {
      final earliest = previous.startUtc.isBefore(floor)
          ? floor
          : previous.startUtc;
      final joined = _cyclesEndingAt(
        wake: next.endUtc,
        earliest: earliest,
        target: target,
        std: std,
      );
      if (joined != null) {
        merged[merged.length - 1] = _SleepWindow(
          startUtc: joined.startUtc,
          endUtc: joined.endUtc,
          earlyShowUp: next.earlyShowUp,
          detail: next.detail ?? (next.earlyShowUp ? null : previous.detail),
        );
        continue;
      }
    }
    merged.add(next);
  }
  return merged;
}

List<_SleepWindow> _sleepWindows(
  JetlagScheduleSnapshot schedule,
  JetlagLifestyle lifestyle,
  UserSettings settings,
) {
  final sta = schedule.staUtc.toUtc();
  final std = schedule.stdUtc.toUtc();
  final clock = _modeClock(schedule, lifestyle, settings);
  final pickup = schedule.pickupUtc?.toUtc();
  final earliest = sta.add(settings.arrivalToSleep);
  final windows = <_SleepWindow>[];
  for (final day in _nightsCovering(clock.zone, sta, std)) {
    final night = clock.nightOn(day);
    final bed = night.bed;
    final wake = night.wake;
    final clipped = bed.isBefore(earliest) ? earliest : bed;
    final end = _wakeOnPickupNight(
      bed: bed,
      wake: wake,
      start: clipped,
      pickup: pickup,
    );
    if (!end.isAfter(clipped)) continue;
    if (end.difference(clipped) < kSleepCycle) continue;
    if (!clipped.isBefore(std) || !end.isAfter(sta)) continue;
    if (clipped.isAfter(bed)) {
      final aligned = _cyclesEndingAt(
        wake: end,
        earliest: clipped,
        target: settings.sleepTarget,
        std: std,
      );
      if (aligned == null) continue;
      windows.add(aligned);
      continue;
    }
    windows.add(_SleepWindow(startUtc: clipped, endUtc: end));
  }
  return _withHomeDeparture(schedule, settings, windows);
}

/// Calendar days of the mode clock, plus the day before arrival so a night
/// already in progress is included.
List<DateTime> _nightsCovering(String zone, DateTime sta, DateTime std) {
  final days = calendarDays(zone, sta, std);
  if (days.isEmpty) return days;
  final first = days.first;
  days.insert(0, DateTime(first.year, first.month, first.day - 1));
  return days;
}

/// Pulls wake forward only on the night that contains [pickup], and only
/// when the earlier wake still leaves a sleep after [start].
DateTime _wakeOnPickupNight({
  required DateTime bed,
  required DateTime wake,
  required DateTime start,
  required DateTime? pickup,
}) {
  if (pickup == null) return wake;
  final contains = !pickup.isBefore(bed) && pickup.isBefore(wake);
  if (!contains) return wake;
  final ready = pickup.subtract(kSleepCycle);
  if (!ready.isAfter(start)) return wake;
  return ready.isBefore(wake) ? ready : wake;
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

String _preDepartureDetail(JetlagScheduleSnapshot schedule) {
  return schedule.pickupUtc == null
      ? '출발 시각에 맞춰 잡은 수면입니다.'
      : '출발 전 픽업에 맞춰 잡은 수면입니다.';
}

/// Pickup when the layover has one. Otherwise the outbound departure minus
/// the home show-up lead.
DateTime? _departureAnchor(
  JetlagScheduleSnapshot schedule,
  UserSettings settings,
) {
  final pickup = schedule.pickupUtc?.toUtc();
  if (pickup != null) return pickup;
  final std = schedule.stdUtc.toUtc();
  if (!std.isAfter(schedule.staUtc.toUtc())) return null;
  return std.subtract(settings.homeShowupLead);
}

/// True when [instant] sits in the mode night, from bedtime up to wake.
/// Hybrid uses the shifted home clock. Wake itself is morning, not night.
bool _inModeNight(DateTime instant, _ModeClock clock) {
  final utc = instant.toUtc();
  final wall = wallClock(utc, clock.zone);
  final day = DateTime(wall.year, wall.month, wall.day);
  for (final delta in const [-1, 0, 1]) {
    final night = clock.nightOn(DateTime(day.year, day.month, day.day + delta));
    if (!utc.isBefore(night.bed) && utc.isBefore(night.wake)) return true;
  }
  return false;
}

class _ModeClock {
  const _ModeClock({
    required this.zone,
    required this.shift,
    required this.bedMinute,
    required this.wakeMinute,
  });

  final String zone;
  final Duration shift;
  final int bedMinute;
  final int wakeMinute;

  DateTime at(DateTime day, int minuteOfDay) {
    return zonedUtc(
      iana: zone,
      year: day.year,
      month: day.month,
      day: day.day,
      hour: minuteOfDay ~/ 60,
      minute: minuteOfDay % 60,
      shift: shift,
    );
  }

  ({DateTime bed, DateTime wake}) nightOn(DateTime day) {
    final bed = at(day, bedMinute);
    var wake = at(day, wakeMinute);
    if (!wake.isAfter(bed)) {
      final next = DateTime(day.year, day.month, day.day + 1);
      wake = at(next, wakeMinute);
    }
    return (bed: bed, wake: wake);
  }
}

_ModeClock _modeClock(
  JetlagScheduleSnapshot schedule,
  JetlagLifestyle lifestyle,
  UserSettings settings,
) {
  final sta = schedule.staUtc.toUtc();
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
  return _ModeClock(
    zone: zone,
    shift: shift,
    bedMinute: settings.defaultBedTime.minuteOfDay,
    wakeMinute: settings.defaultWakeTime.minuteOfDay,
  );
}

int _cycleCount(Duration available, Duration target) {
  if (available < kSleepCycle || target < kSleepCycle) return 0;
  final byWindow = available.inMinutes ~/ kSleepCycle.inMinutes;
  final byTarget = target.inMinutes ~/ kSleepCycle.inMinutes;
  final count = byWindow < byTarget ? byWindow : byTarget;
  return count < 1 ? 0 : count;
}

/// End stays on [wake]. The start moves later in 90-minute steps so the
/// block is the longest multiple of a cycle that fits [target] and still
/// begins at or after [earliest].
_SleepWindow? _cyclesEndingAt({
  required DateTime wake,
  required DateTime earliest,
  required Duration target,
  required DateTime std,
}) {
  if (!wake.isAfter(earliest)) return null;
  final cycles = _cycleCount(wake.difference(earliest), target);
  if (cycles < 1) return null;
  final start = wake.subtract(
    Duration(minutes: kSleepCycle.inMinutes * cycles),
  );
  if (start.isBefore(earliest) ||
      !start.isBefore(std) ||
      !wake.isAfter(start)) {
    return null;
  }
  return _SleepWindow(startUtc: start, endUtc: wake);
}

/// First sleep after arrival when the daily loop produced nothing.
///
/// A segment that cannot hold one 90-minute cycle is dropped. The next
/// mode bedtime is used instead. The earliest start on the arrival side is
/// arrival + [UserSettings.arrivalToSleep].
List<_SleepWindow> _firstSleepAfterArrival(
  JetlagScheduleSnapshot schedule,
  JetlagLifestyle lifestyle,
  UserSettings settings,
) {
  final sta = schedule.staUtc.toUtc();
  final std = schedule.stdUtc.toUtc();
  final clock = _modeClock(schedule, lifestyle, settings);
  final wall = wallClock(sta, clock.zone);
  final origin = DateTime(wall.year, wall.month, wall.day);
  final nights = <({DateTime bed, DateTime wake})>[
    for (var delta = -1; delta <= 4; delta++)
      clock.nightOn(DateTime(origin.year, origin.month, origin.day + delta)),
  ];
  final ready = sta.add(settings.arrivalToSleep);
  final containing = nights
      .where((night) => !sta.isBefore(night.bed) && sta.isBefore(night.wake))
      .firstOrNull;
  if (containing != null) {
    final during = _cyclesEndingAt(
      wake: containing.wake,
      earliest: ready.isAfter(containing.bed) ? ready : containing.bed,
      target: settings.sleepTarget,
      std: std,
    );
    if (during != null) return [during];
    final next = nights
        .where((night) => !night.bed.isBefore(containing.wake))
        .firstOrNull;
    if (next == null) return const [];
    final moved = _cyclesEndingAt(
      wake: next.wake,
      earliest: next.bed,
      target: settings.sleepTarget,
      std: std,
    );
    return moved == null ? const [] : [moved];
  }

  final upcoming = nights
      .where((night) => !night.bed.isBefore(sta))
      .firstOrNull;
  if (upcoming == null) return const [];
  final wokeAlready = nights.any(
    (night) => !night.wake.isAfter(sta) && night.wake.isAfter(night.bed),
  );
  if (wokeAlready && sta.isBefore(upcoming.bed)) {
    final napEnd = ready.add(kSleepCycle);
    if (!napEnd.isAfter(upcoming.bed) &&
        napEnd.isAfter(ready) &&
        ready.isBefore(std) &&
        !ready.isBefore(sta)) {
      return [_SleepWindow(startUtc: ready, endUtc: napEnd)];
    }
  }
  final night = _cyclesEndingAt(
    wake: upcoming.wake,
    earliest: upcoming.bed.isBefore(ready) ? ready : upcoming.bed,
    target: settings.sleepTarget,
    std: std,
  );
  return night == null ? const [] : [night];
}
