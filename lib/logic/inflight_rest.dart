import '../models/lifestyle.dart';
import '../models/user_settings.dart';
import 'home_base_timezone.dart';
import 'hybrid_strategy.dart';
import 'jetlag_clock.dart';
import 'sleep_constants.dart';

/// Reference rest window on one flight.
///
/// The night is the body clock at boarding, moved toward the destination
/// by [inflightShift]. The window is where that night meets the cruise
/// (takeoff + [kInflightAfterTakeoff] through landing − [kInflightBeforeLanding]).
class InflightRestWindow {
  const InflightRestWindow({
    required this.startUtc,
    required this.endUtc,
    required this.inflightShift,
    required this.shortOverlap,
    required this.detail,
  });

  final DateTime startUtc;
  final DateTime endUtc;
  final Duration inflightShift;

  /// True when the shifted night meets the cruise for less than one cycle.
  final bool shortOverlap;
  final String detail;
}

/// Body-clock night at boarding, plus a limited move toward the destination.
///
/// A flight that leaves home uses the home night. A flight that leaves the
/// layover uses the mode night already in use there: home, home plus the
/// hybrid shift, or the station night. No extra state is stored.
InflightRestWindow? inflightRestWindow({
  required DateTime stdUtc,
  required DateTime staUtc,
  required String originZone,
  required String destinationZone,
  required String homeZone,
  required JetlagLifestyle lifestyle,
  UserSettings settings = UserSettings.defaults,
}) {
  final std = stdUtc.toUtc();
  final sta = staUtc.toUtc();
  final cruiseStart = std.add(kInflightAfterTakeoff);
  final cruiseEnd = sta.subtract(kInflightBeforeLanding);
  if (!cruiseEnd.isAfter(cruiseStart)) return null;

  final home = resolveHomeBaseTimezone(homeZone);
  final origin = originZone.trim().isEmpty ? home : originZone.trim();
  final destination = destinationZone.trim().isEmpty
      ? home
      : destinationZone.trim();
  final leavingHome = _sameZone(origin, home);
  final station = leavingHome ? destination : origin;
  final body = _bodyShift(
    leavingHome: leavingHome,
    lifestyle: lifestyle,
    homeZone: home,
    stationZone: station,
    at: std,
    settings: settings,
  );
  final inflight = _inflightShift(
    lifestyle: lifestyle,
    originZone: origin,
    destinationZone: destination,
    bodyShift: body,
    homeZone: home,
    at: std,
    settings: settings,
  );
  final nightShift = body + inflight;
  final night = _closestNight(
    homeZone: home,
    shift: nightShift,
    bedMinute: settings.defaultBedTime.minuteOfDay,
    wakeMinute: settings.defaultWakeTime.minuteOfDay,
    cruiseStart: cruiseStart,
    cruiseEnd: cruiseEnd,
  );
  final overlap = _overlap(night.bed, night.wake, cruiseStart, cruiseEnd);
  final short = overlap < kSleepCycle;
  final span = short
      ? _nearestCruiseSlice(night, cruiseStart, cruiseEnd)
      : _clipped(night.bed, night.wake, cruiseStart, cruiseEnd);
  return InflightRestWindow(
    startUtc: span.start,
    endUtc: span.end,
    inflightShift: inflight,
    shortOverlap: short,
    detail: _detail(
      homeZone: home,
      shift: inflight,
      shortOverlap: short,
    ),
  );
}

Duration _bodyShift({
  required bool leavingHome,
  required JetlagLifestyle lifestyle,
  required String homeZone,
  required String stationZone,
  required DateTime at,
  required UserSettings settings,
}) {
  if (leavingHome || lifestyle == JetlagLifestyle.kstAnchor) {
    return Duration.zero;
  }
  if (lifestyle == JetlagLifestyle.hybrid) {
    return const HybridStrategy().shift(
      zoneOffset: zoneOffset(at, stationZone, homeZone),
      maxShift: Duration(hours: settings.hybridMaxShiftHours),
    );
  }
  return _shortArc(homeZone, stationZone, at);
}

Duration _inflightShift({
  required JetlagLifestyle lifestyle,
  required String originZone,
  required String destinationZone,
  required Duration bodyShift,
  required String homeZone,
  required DateTime at,
  required UserSettings settings,
}) {
  if (lifestyle == JetlagLifestyle.kstAnchor) return Duration.zero;
  final towardDestination = _shortArc(originZone, destinationZone, at);
  final Duration desired;
  if (lifestyle == JetlagLifestyle.hybrid) {
    final ground = const HybridStrategy().shift(
      zoneOffset: zoneOffset(at, destinationZone, originZone),
      maxShift: Duration(hours: settings.hybridMaxShiftHours),
    );
    desired = Duration(minutes: ground.inMinutes ~/ 2);
  } else {
    desired = _capAbs(towardDestination, kInflightMaxShift);
  }
  final remaining = _shortArc(homeZone, destinationZone, at) - bodyShift;
  return _limit(desired, remaining);
}

/// Short-arc move from [fromZone] onto [toZone], same sign as Hybrid.
/// Negative is earlier (eastbound). Positive is later (westbound).
Duration _shortArc(String fromZone, String toZone, DateTime at) {
  return const HybridStrategy().shift(
    zoneOffset: zoneOffset(at, toZone, fromZone),
    maxShift: const Duration(hours: 12),
  );
}

Duration _capAbs(Duration direction, Duration cap) {
  if (direction.inMinutes == 0 || cap.inMinutes <= 0) return Duration.zero;
  final minutes = direction.inMinutes.abs() < cap.inMinutes
      ? direction.inMinutes.abs()
      : cap.inMinutes;
  return Duration(minutes: direction.isNegative ? -minutes : minutes);
}

Duration _limit(Duration desired, Duration remaining) {
  if (desired.inMinutes == 0 || remaining.inMinutes == 0) {
    return Duration.zero;
  }
  if ((desired.inMinutes > 0) != (remaining.inMinutes > 0)) {
    return Duration.zero;
  }
  final minutes = desired.inMinutes.abs() < remaining.inMinutes.abs()
      ? desired.inMinutes.abs()
      : remaining.inMinutes.abs();
  return Duration(minutes: desired.isNegative ? -minutes : minutes);
}

class _Night {
  const _Night(this.bed, this.wake);

  final DateTime bed;
  final DateTime wake;
}

_Night _closestNight({
  required String homeZone,
  required Duration shift,
  required int bedMinute,
  required int wakeMinute,
  required DateTime cruiseStart,
  required DateTime cruiseEnd,
}) {
  final wall = wallClock(cruiseStart, homeZone);
  final origin = DateTime(wall.year, wall.month, wall.day);
  _Night? best;
  var bestScore = 1 << 30;
  for (var delta = -1; delta <= 2; delta++) {
    final day = DateTime(origin.year, origin.month, origin.day + delta);
    final night = _nightOn(homeZone, day, bedMinute, wakeMinute, shift);
    final score = _gapScore(night.bed, night.wake, cruiseStart, cruiseEnd);
    if (score < bestScore) {
      bestScore = score;
      best = night;
    }
  }
  return best!;
}

_Night _nightOn(
  String zone,
  DateTime day,
  int bedMinute,
  int wakeMinute,
  Duration shift,
) {
  final bed = _at(zone, day, bedMinute, shift);
  var wake = _at(zone, day, wakeMinute, shift);
  if (!wake.isAfter(bed)) {
    final next = DateTime(day.year, day.month, day.day + 1);
    wake = _at(zone, next, wakeMinute, shift);
  }
  return _Night(bed, wake);
}

DateTime _at(String zone, DateTime day, int minuteOfDay, Duration shift) {
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

/// Negative when the ranges overlap. A longer overlap scores lower.
int _gapScore(DateTime a0, DateTime a1, DateTime b0, DateTime b1) {
  final overlap = _overlap(a0, a1, b0, b1);
  if (overlap > Duration.zero) return -overlap.inMinutes;
  if (!a1.isAfter(b0)) return b0.difference(a1).inMinutes;
  return a0.difference(b1).inMinutes;
}

Duration _overlap(DateTime a0, DateTime a1, DateTime b0, DateTime b1) {
  final start = a0.isAfter(b0) ? a0 : b0;
  final end = a1.isBefore(b1) ? a1 : b1;
  if (!end.isAfter(start)) return Duration.zero;
  return end.difference(start);
}

({DateTime start, DateTime end}) _clipped(
  DateTime bed,
  DateTime wake,
  DateTime cruiseStart,
  DateTime cruiseEnd,
) {
  final start = bed.isAfter(cruiseStart) ? bed : cruiseStart;
  final end = wake.isBefore(cruiseEnd) ? wake : cruiseEnd;
  return (start: start, end: end);
}

({DateTime start, DateTime end}) _nearestCruiseSlice(
  _Night night,
  DateTime cruiseStart,
  DateTime cruiseEnd,
) {
  final nightSpan = night.wake.difference(night.bed);
  final flightSpan = cruiseEnd.difference(cruiseStart);
  final nightCenter = night.bed.add(nightSpan ~/ 2);
  final flightCenter = cruiseStart.add(flightSpan ~/ 2);
  if (!nightCenter.isAfter(flightCenter)) {
    var end = cruiseStart.add(kSleepCycle);
    if (end.isAfter(cruiseEnd)) end = cruiseEnd;
    return (start: cruiseStart, end: end);
  }
  var start = cruiseEnd.subtract(kSleepCycle);
  if (start.isBefore(cruiseStart)) start = cruiseStart;
  return (start: start, end: cruiseEnd);
}

String _detail({
  required String homeZone,
  required Duration shift,
  required bool shortOverlap,
}) {
  final moved = shift.inMinutes == 0
      ? '${_homeBaseWord(homeZone)} 기준 밤에 가까운 시간대예요.'
      : '몸시계 기준 밤을 목적지 쪽으로 ${_shiftLabel(shift)} 옮긴 시간대예요.';
  final crew = '실제 휴식은 크루 휴식 배정에 따릅니다.';
  final short = shortOverlap ? ' 몸시계 밤과 겹치는 시간이 짧아요.' : '';
  return '$moved $crew$short';
}

String _homeBaseWord(String homeZone) {
  final name = homeClockName(homeZone);
  if (name == '한국시간') return '한국';
  return name;
}

String _shiftLabel(Duration shift) {
  final minutes = shift.inMinutes.abs();
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '$mins분';
  if (mins == 0) return '$hours시간';
  return '$hours시간 $mins분';
}

bool _sameZone(String a, String b) => a.trim() == b.trim();
