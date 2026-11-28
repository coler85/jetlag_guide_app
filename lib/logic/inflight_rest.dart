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
    required this.missedNight,
    required this.headline,
    required this.supplement,
    required this.detail,
  });

  final DateTime startUtc;
  final DateTime endUtc;
  final Duration inflightShift;

  /// True when the shifted night meets the cruise for less than one cycle.
  final bool shortOverlap;

  /// True when the night misses the cruise and the window is the nearest slice.
  final bool missedNight;

  /// White headline on the standalone inflight card.
  final String headline;

  /// Gray follow-up under the reference line (crew assignment / top-up).
  final String supplement;

  /// [headline] and [supplement] joined; kept for the standalone event card.
  final String detail;
}

/// Dual-zone reference line for the inflight timeline card and the bunk card.
///
/// Overlap keeps "겹치는 시간"; a full miss (nearest slice) uses "가까운 시간".
/// Home is always a start–end range. No UTC(Z).
String inflightRestReferenceLine({
  required DateTime startUtc,
  required DateTime endUtc,
  required bool missedNight,
  required String localIana,
  required String localTag,
  required String homeIana,
}) {
  final localRange =
      '${formatHm(startUtc, localIana)}–${formatHm(endUtc, localIana)}';
  final homeRange =
      '${formatHm(startUtc, homeIana)}–${formatHm(endUtc, homeIana)}';
  final abbr = zoneAbbreviation(startUtc.toUtc(), homeIana);
  final label = missedNight ? '생체시계 밤에 가까운 시간' : '생체시계 밤과 겹치는 시간';
  return '$label $localRange ($localTag) · $homeRange $abbr';
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
  final nightInfo = bodyClockNightForFlight(
    stdUtc: std,
    staUtc: sta,
    originZone: origin,
    destinationZone: destination,
    homeZone: home,
    lifestyle: lifestyle,
    settings: settings,
  );
  if (nightInfo == null) return null;
  final night = _Night(nightInfo.bedUtc, nightInfo.wakeUtc);
  final overlap = _overlap(night.bed, night.wake, cruiseStart, cruiseEnd);
  final short = overlap < kSleepCycle;
  final missed = overlap == Duration.zero;
  // Short but non-zero overlap keeps the real clipped span. Only a full miss
  // falls back to the nearest cruise slice of one sleep cycle.
  final span = missed
      ? _nearestCruiseSlice(night, cruiseStart, cruiseEnd)
      : _clipped(night.bed, night.wake, cruiseStart, cruiseEnd);
  final endsRightAfterTakeoff =
      !missed && span.start.isAtSameMomentAs(cruiseStart);
  final copy = _copy(
    homeZone: home,
    lifestyle: lifestyle,
    shift: inflight,
    overlap: overlap,
    endsRightAfterTakeoff: endsRightAfterTakeoff,
  );
  return InflightRestWindow(
    startUtc: span.start,
    endUtc: span.end,
    inflightShift: inflight,
    shortOverlap: short,
    missedNight: missed,
    headline: copy.headline,
    supplement: copy.supplement,
    detail: '${copy.headline} ${copy.supplement}',
  );
}

/// Body-clock rest for the flight that leaves the layover.
///
/// Same STD / block / zones the bunk card and the synthesized return leg use.
InflightRestWindow? layoverReturnInflightRest({
  required DateTime stdUtc,
  required int blockMinutes,
  required String originZone,
  required String destinationZone,
  required String homeZone,
  required JetlagLifestyle lifestyle,
  UserSettings settings = UserSettings.defaults,
}) {
  if (blockMinutes <= 0) return null;
  final std = stdUtc.toUtc();
  final sta = std.add(Duration(minutes: blockMinutes));
  if (!sta.isAfter(std)) return null;
  return inflightRestWindow(
    stdUtc: std,
    staUtc: sta,
    originZone: originZone,
    destinationZone: destinationZone,
    homeZone: homeZone,
    lifestyle: lifestyle,
    settings: settings,
  );
}

/// Full body-clock night (bed–wake) used by [inflightRestWindow] on a flight.
///
/// Same mode clock and [inflightShift] as the cruise reference window. The
/// night is not clipped to cruise; bunk overlap compares against this span.
class BodyClockNight {
  const BodyClockNight({required this.bedUtc, required this.wakeUtc});

  final DateTime bedUtc;
  final DateTime wakeUtc;
}

/// The closest body-clock night for a flight, scored against the cruise.
BodyClockNight? bodyClockNightForFlight({
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
  final night = _closestNight(
    homeZone: home,
    shift: body + inflight,
    bedMinute: settings.defaultBedTime.minuteOfDay,
    wakeMinute: settings.defaultWakeTime.minuteOfDay,
    cruiseStart: cruiseStart,
    cruiseEnd: cruiseEnd,
  );
  return BodyClockNight(bedUtc: night.bed, wakeUtc: night.wake);
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

({String headline, String supplement}) _copy({
  required String homeZone,
  required JetlagLifestyle lifestyle,
  required Duration shift,
  required Duration overlap,
  required bool endsRightAfterTakeoff,
}) {
  final subject = _nightSubject(homeZone: homeZone, lifestyle: lifestyle);
  final cycleMinutes = kSleepCycle.inMinutes;
  final topUp =
      '실제 휴식은 크루 배정에 따르고, 컨디션에 맞춰 $cycleMinutes'
      '분 이내로 잠을 보충해 보세요.';
  const crewOnly = '실제 휴식은 크루 배정에 따릅니다.';
  if (overlap == Duration.zero) {
    return (headline: '$subject과 겹치지 않아요.', supplement: topUp);
  }
  if (overlap < kSleepCycle) {
    final lead = endsRightAfterTakeoff
        ? '$subject이 이륙 직후 끝나서 겹치는 시간이 짧아요.'
        : '$subject과 겹치는 시간이 짧아요.';
    return (headline: lead, supplement: topUp);
  }
  final moved = shift.inMinutes == 0
      ? '${_homeBaseWord(homeZone)} 기준 밤에 가까운 시간대예요.'
      : '생체시계 기준 밤을 목적지 쪽으로 ${_shiftLabel(shift)} 옮긴 시간대예요.';
  return (headline: moved, supplement: crewOnly);
}

/// kstAnchor on a Korean home base says "한국 밤"; everything else is body-clock night.
String _nightSubject({
  required String homeZone,
  required JetlagLifestyle lifestyle,
}) {
  if (lifestyle == JetlagLifestyle.kstAnchor &&
      homeClockName(homeZone) == '한국시간') {
    return '한국 밤';
  }
  return '생체시계 밤';
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
