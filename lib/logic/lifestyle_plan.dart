import '../models/arrival_order.dart';
import '../models/guide_event.dart';
import '../models/jetlag_schedule.dart';
import '../models/lifestyle.dart';
import '../models/user_settings.dart';
import 'home_base_timezone.dart';
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
///
/// [inboundStdUtc] is the departing instant of the inbound leg. When null,
/// overnight-flight naps are not added.
List<GuideEvent> lifestyleBlocks({
  required JetlagScheduleSnapshot schedule,
  required JetlagLifestyle lifestyle,
  UserSettings settings = UserSettings.defaults,
  DateTime? inboundStdUtc,
}) {
  final sta = schedule.staUtc.toUtc();
  final std = schedule.stdUtc.toUtc();
  if (!std.isAfter(sta)) return const [];

  final windows = _sleepWindows(schedule, lifestyle, settings);
  final seeded = windows.isEmpty
      ? _firstSleepAfterArrival(
          schedule,
          lifestyle,
          settings,
          inboundStdUtc: inboundStdUtc,
        )
      : windows;
  final prepared = _withPreDepartureSleep(
    schedule,
    settings,
    lifestyle,
    seeded,
  );
  var cleared = _clearDutyOverlap(schedule, settings, prepared);
  if (cleared.isEmpty && prepared.isNotEmpty) {
    cleared = _clearDutyOverlap(
      schedule,
      settings,
      _firstSleepAfterArrival(
        schedule,
        lifestyle,
        settings,
        inboundStdUtc: inboundStdUtc,
      ),
    );
  }
  var sleeps = _mergeCloseSleeps(
    cleared,
    floor: sta.add(settings.arrivalToSleep),
    target: settings.sleepTarget,
    std: std,
  );
  sleeps = _withOvernightNap(
    schedule,
    lifestyle,
    settings,
    sleeps,
    inboundStdUtc: inboundStdUtc,
  );
  final arrivalSleep = _immediateArrivalSleep(sleeps, sta, settings);
  final westboundSleep = _lastSleepBeforeDeparture(sleeps, std);
  final appendWestbound = _shouldAppendWestboundEveningNote(schedule, lifestyle);
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
    final isArrival = identical(sleep, arrivalSleep) ||
        (arrivalSleep != null &&
            sleep.startUtc == arrivalSleep.startUtc &&
            sleep.endUtc == arrivalSleep.endUtc);
    blocks.addAll(
      _arrivalAwareMeals(
        sleep: sleep,
        next: next,
        sta: sta,
        std: std,
        sleeps: sleeps,
        settings: settings,
        isArrivalSleep: isArrival,
      ),
    );
    var detail = sleep.detail ??
        (sleep.earlyShowUp
            ? _preDepartureDetail(schedule)
            : lifestyle.sleepDetailFor(
                schedule.referenceTimeZone,
                hybridMaxShiftHours: settings.hybridMaxShiftHours,
              ));
    if (appendWestbound &&
        westboundSleep != null &&
        sleep.startUtc == westboundSleep.startUtc &&
        sleep.endUtc == westboundSleep.endUtc) {
      detail = '$detail ${_westboundEveningNote(schedule)}';
    }
    blocks.add(
      GuideEvent(
        id: 'sleep-${sleep.startUtc.microsecondsSinceEpoch}',
        kind: GuideEventKind.sleep,
        startUtc: sleep.startUtc,
        endUtc: sleep.endUtc,
        title: '수면',
        detail: detail,
      ),
    );
    final light = _lightAfterSleep(sleep, next, sta, std);
    if (light != null) blocks.add(light);
  }
  return blocks;
}

/// First sleep that starts after hotel arrival and within [kArrivalSleepSoon].
_SleepWindow? _immediateArrivalSleep(
  List<_SleepWindow> sleeps,
  DateTime sta,
  UserSettings settings,
) {
  final hotel = settings.hotelArrivalUtc(sta);
  final sorted = [...sleeps]..sort((a, b) => a.startUtc.compareTo(b.startUtc));
  for (final sleep in sorted) {
    if (!sleep.startUtc.isAfter(hotel)) continue;
    if (sleep.startUtc.difference(hotel) <= kArrivalSleepSoon) return sleep;
  }
  return null;
}

_SleepWindow? _lastSleepBeforeDeparture(
  List<_SleepWindow> sleeps,
  DateTime std,
) {
  _SleepWindow? last;
  for (final sleep in sleeps) {
    if (!sleep.endUtc.isBefore(std)) continue;
    if (last == null || sleep.endUtc.isAfter(last.endUtc)) last = sleep;
  }
  return last;
}

List<GuideEvent> _arrivalAwareMeals({
  required _SleepWindow sleep,
  required _SleepWindow? next,
  required DateTime sta,
  required DateTime std,
  required List<_SleepWindow> sleeps,
  required UserSettings settings,
  required bool isArrivalSleep,
}) {
  if (!isArrivalSleep) {
    return _preSleepMeal(sleep: sleep, sta: sta, std: std, sleeps: sleeps);
  }

  final mealReady = settings.hotelArrivalUtc(sta);
  final gap = sleep.startUtc.difference(mealReady);
  final order = settings.arrivalOrder;
  final restFirstStyle =
      order == ArrivalOrder.restFirst ||
      (order != ArrivalOrder.mealFirst && gap < kMealLead);

  if (order == ArrivalOrder.mealFirst && gap < kMealLead) {
    return _mealBeforeSleep(
      at: mealReady,
      sta: sta,
      std: std,
      sleeps: sleeps,
      sleep: sleep,
      title: '식사',
      detail: '가볍게 먹고 바로 쉬어요.',
      idPrefix: 'meal',
    );
  }

  if (restFirstStyle) {
    final events = <GuideEvent>[
      ..._mealBeforeSleep(
        at: mealReady,
        sta: sta,
        std: std,
        sleeps: sleeps,
        sleep: sleep,
        title: '간식',
        detail: '배고프면 가볍게만 먹고 쉬어요. 식사는 일어난 뒤에 해요.',
        idPrefix: 'snack',
      ),
    ];
    final wakeMeal = sleep.endUtc;
    final nextQuiet = next?.startUtc.subtract(kMealLead);
    final wakeOk = wakeMeal.isBefore(std) &&
        (nextQuiet == null || wakeMeal.isBefore(nextQuiet)) &&
        !wakeMeal.isBefore(sta) &&
        !_insideSleep(wakeMeal, sleeps);
    if (wakeOk) {
      events.add(
        GuideEvent(
          id: 'meal-${wakeMeal.microsecondsSinceEpoch}',
          kind: GuideEventKind.meal,
          startUtc: wakeMeal,
          title: '식사',
          detail: '일어난 뒤 먹어요.',
        ),
      );
    }
    return events;
  }

  return _preSleepMeal(sleep: sleep, sta: sta, std: std, sleeps: sleeps);
}

List<GuideEvent> _preSleepMeal({
  required _SleepWindow sleep,
  required DateTime sta,
  required DateTime std,
  required List<_SleepWindow> sleeps,
}) {
  return _mealBeforeSleep(
    at: sleep.startUtc.subtract(kMealLead),
    sta: sta,
    std: std,
    sleeps: sleeps,
    sleep: sleep,
    title: '식사',
    detail: '잠들기 전 식사.',
    idPrefix: 'meal',
  );
}

List<GuideEvent> _mealBeforeSleep({
  required DateTime at,
  required DateTime sta,
  required DateTime std,
  required List<_SleepWindow> sleeps,
  required _SleepWindow sleep,
  required String title,
  required String detail,
  required String idPrefix,
}) {
  if (at.isBefore(sta) || !at.isBefore(std)) return const [];
  if (!at.isBefore(sleep.startUtc)) return const [];
  if (_insideSleep(at, sleeps)) return const [];
  return [
    GuideEvent(
      id: '$idPrefix-${at.microsecondsSinceEpoch}',
      kind: GuideEventKind.meal,
      startUtc: at,
      title: title,
      detail: detail,
    ),
  ];
}

/// Westbound when the folded (home − local) offset is negative.
///
/// Fold into (−12h, +12h]. Example: Seoul (+9) vs LA (−8) → +17 → −7.
bool isWestboundOffset({
  required DateTime at,
  required String homeZone,
  required String localZone,
}) {
  final raw = wallClock(at, homeZone).timeZoneOffset -
      wallClock(at, localZone).timeZoneOffset;
  return _foldHalfDay(raw).isNegative;
}

Duration _foldHalfDay(Duration offset) {
  var minutes = offset.inMinutes % (24 * 60);
  if (minutes < 0) minutes += 24 * 60;
  if (minutes > 12 * 60) minutes -= 24 * 60;
  return Duration(minutes: minutes);
}

bool _shouldAppendWestboundEveningNote(
  JetlagScheduleSnapshot schedule,
  JetlagLifestyle lifestyle,
) {
  if (lifestyle != JetlagLifestyle.kstAnchor) return false;
  final std = schedule.stdUtc.toUtc();
  final local = wallClock(std, schedule.localTimeZone);
  if (local.hour < kEveningDepartureStart) return false;
  return isWestboundOffset(
    at: std,
    homeZone: schedule.referenceTimeZone,
    localZone: schedule.localTimeZone,
  );
}

String _westboundEveningNote(JetlagScheduleSnapshot schedule) {
  final home = homeClockName(schedule.referenceTimeZone);
  return '저녁에 서쪽으로 떠나는 편이에요. $home을 그대로 두는 날이라 출발 전 수면이 특히 중요해요.';
}

const _overnightNapDetail =
    '밤샘 비행 뒤 짧은 낮잠이에요. 밤 수면 전에 끝나게 잡았어요.';

/// Nap cycles that fit before [nightBed] − [kNapGapBeforeNight], capped by
/// [maxCycles].
int napCycleCount({
  required DateTime ready,
  required DateTime nightBed,
  required int maxCycles,
}) {
  final latestEnd = nightBed.subtract(kNapGapBeforeNight);
  if (!latestEnd.isAfter(ready)) return 0;
  final byWindow = latestEnd.difference(ready).inMinutes ~/ kSleepCycle.inMinutes;
  final capped = byWindow < maxCycles ? byWindow : maxCycles;
  return capped < 1 ? 0 : capped;
}

bool _isOvernightFlight(
  DateTime inboundStd,
  DateTime sta,
  _ModeClock clock,
) {
  if (!sta.isAfter(inboundStd)) return false;
  var total = Duration.zero;
  final wall = wallClock(inboundStd, clock.zone);
  final origin = DateTime(wall.year, wall.month, wall.day);
  final endWall = wallClock(sta, clock.zone);
  final last = DateTime(endWall.year, endWall.month, endWall.day);
  for (
    var day = DateTime(origin.year, origin.month, origin.day - 1);
    !day.isAfter(DateTime(last.year, last.month, last.day + 1));
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    final night = clock.nightOn(day);
    final overlapStart =
        inboundStd.isAfter(night.bed) ? inboundStd : night.bed;
    final overlapEnd = sta.isBefore(night.wake) ? sta : night.wake;
    if (overlapEnd.isAfter(overlapStart)) {
      total += overlapEnd.difference(overlapStart);
    }
  }
  return total >= kOvernightFlightMin;
}

List<_SleepWindow> _withOvernightNap(
  JetlagScheduleSnapshot schedule,
  JetlagLifestyle lifestyle,
  UserSettings settings,
  List<_SleepWindow> sleeps, {
  DateTime? inboundStdUtc,
}) {
  if (inboundStdUtc == null) return sleeps;
  final sta = schedule.staUtc.toUtc();
  final std = schedule.stdUtc.toUtc();
  final clock = _modeClock(schedule, lifestyle, settings);
  final inbound = inboundStdUtc.toUtc();
  if (!_isOvernightFlight(inbound, sta, clock)) return sleeps;
  if (_inModeNight(sta, clock)) return sleeps;

  final ready = sta.add(settings.arrivalToSleep);
  if (!ready.isBefore(std) || ready.isBefore(sta)) return sleeps;
  final upcoming = _upcomingModeBed(clock, sta);
  if (upcoming == null) return sleeps;
  final cycles = napCycleCount(
    ready: ready,
    nightBed: upcoming,
    maxCycles: kNapMaxCycles,
  );
  if (cycles < 1) return sleeps;
  final napEnd = ready.add(
    Duration(minutes: kSleepCycle.inMinutes * cycles),
  );
  if (!napEnd.isAfter(ready) || napEnd.isAfter(upcoming)) return sleeps;
  final nap = _SleepWindow(
    startUtc: ready,
    endUtc: napEnd,
    detail: _overnightNapDetail,
  );
  if (sleeps.any(
    (sleep) => _rangesOverlap(
      sleep.startUtc,
      sleep.endUtc,
      nap.startUtc,
      nap.endUtc,
    ),
  )) {
    return sleeps;
  }
  final next = [...sleeps, nap]..sort((a, b) => a.startUtc.compareTo(b.startUtc));
  return next;
}

DateTime? _upcomingModeBed(_ModeClock clock, DateTime sta) {
  final wall = wallClock(sta, clock.zone);
  final origin = DateTime(wall.year, wall.month, wall.day);
  for (var delta = 0; delta <= 4; delta++) {
    final night = clock.nightOn(
      DateTime(origin.year, origin.month, origin.day + delta),
    );
    if (!night.bed.isBefore(sta)) return night.bed;
  }
  return null;
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
  return _withHomeDeparture(schedule, settings, lifestyle, windows);
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
  JetlagLifestyle lifestyle,
  List<_SleepWindow> windows,
) {
  final clock = _modeClock(schedule, lifestyle, settings);
  final plan = const HomeDepartureAdvisor().evaluate(
    schedule: schedule,
    settings: settings,
    clockZone: clock.zone,
    clockShift: clock.shift,
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

/// Removes mode sleep that overlaps the departing flight's duty.
///
/// Duty runs from the departure report to that flight's STA (STD plus the
/// block). When at least one 90-minute cycle fits before the report, that
/// prefix stays and ends at report − prep − commute. A shorter prefix is
/// dropped. The 3-hour merge runs after this.
List<_SleepWindow> _clearDutyOverlap(
  JetlagScheduleSnapshot schedule,
  UserSettings settings,
  List<_SleepWindow> windows,
) {
  final dutyStart = _dutyStart(schedule, settings);
  if (dutyStart == null || windows.isEmpty) return windows;
  final dutyEnd = schedule.stdUtc.toUtc().add(
    Duration(minutes: schedule.blockMinutes),
  );
  if (!dutyEnd.isAfter(dutyStart)) return windows;
  final std = schedule.stdUtc.toUtc();
  final lead = settings.prepTime + settings.commuteTime;
  final kept = <_SleepWindow>[];
  for (final window in windows) {
    if (!_rangesOverlap(
      window.startUtc,
      window.endUtc,
      dutyStart,
      dutyEnd,
    )) {
      kept.add(window);
      continue;
    }
    final beforeEnd = window.endUtc.isBefore(dutyStart)
        ? window.endUtc
        : dutyStart;
    if (beforeEnd.difference(window.startUtc) < kSleepCycle) continue;
    final block = _cyclesEndingAt(
      wake: dutyStart.subtract(lead),
      earliest: window.startUtc,
      target: settings.sleepTarget,
      std: std,
    );
    if (block == null ||
        _rangesOverlap(block.startUtc, block.endUtc, dutyStart, dutyEnd)) {
      continue;
    }
    kept.add(
      _SleepWindow(
        startUtc: block.startUtc,
        endUtc: block.endUtc,
        earlyShowUp: window.earlyShowUp,
        detail: window.detail,
      ),
    );
  }
  return kept;
}

/// Start of the duty for the flight that leaves at STD.
///
/// The pickup is that start when it falls before departure and not earlier
/// than departure − show-up lead − prep − commute. An earlier pickup stays
/// on the layover, and the duty then starts at departure − show-up lead.
DateTime? _dutyStart(JetlagScheduleSnapshot schedule, UserSettings settings) {
  final std = schedule.stdUtc.toUtc();
  if (!std.isAfter(schedule.staUtc.toUtc())) return null;
  final showup = std.subtract(settings.homeShowupLead);
  final pickup = schedule.pickupUtc?.toUtc();
  if (pickup == null || !pickup.isBefore(std)) return showup;
  final earliest = showup.subtract(settings.prepTime + settings.commuteTime);
  if (pickup.isBefore(earliest)) return showup;
  return pickup;
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
  UserSettings settings, {
  DateTime? inboundStdUtc,
}) {
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
    final overnight = inboundStdUtc != null &&
        _isOvernightFlight(inboundStdUtc.toUtc(), sta, clock);
    final cycles = napCycleCount(
      ready: ready,
      nightBed: upcoming.bed,
      maxCycles: overnight ? kNapMaxCycles : 1,
    );
    if (cycles >= 1 &&
        ready.isBefore(std) &&
        !ready.isBefore(sta)) {
      final napEnd = ready.add(
        Duration(minutes: kSleepCycle.inMinutes * cycles),
      );
      if (napEnd.isAfter(ready) && !napEnd.isAfter(upcoming.bed)) {
        return [
          _SleepWindow(
            startUtc: ready,
            endUtc: napEnd,
            detail: overnight ? _overnightNapDetail : null,
          ),
        ];
      }
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
