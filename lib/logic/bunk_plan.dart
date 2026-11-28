import '../models/bunk_shift.dart';
import '../models/jetlag_schedule.dart';
import '../models/lifestyle.dart';
import '../models/user_settings.dart';
import 'inflight_rest.dart';
import 'jetlag_clock.dart';
import 'sleep_constants.dart';

/// Assigned bunk sleep for one shift. Same cruise bounds as [buildBunkPlan].
({DateTime startUtc, DateTime endUtc}) bunkAssignedRest(
  JetlagScheduleSnapshot schedule,
  BunkShift shift,
) {
  final departure = schedule.stdUtc.toUtc();
  final block = Duration(minutes: schedule.blockMinutes);
  final cruiseStart = departure.add(const Duration(minutes: 90));
  var cruiseEnd = departure.add(block).subtract(const Duration(minutes: 90));
  if (!cruiseEnd.isAfter(cruiseStart)) {
    cruiseEnd = cruiseStart.add(const Duration(hours: 4));
  }
  final cruise = cruiseEnd.difference(cruiseStart);
  final midpoint = cruiseStart.add(cruise ~/ 2);

  final (DateTime sleepStart, Duration sleepLength) = switch (shift) {
    BunkShift.p2EarlyRest => (cruiseStart, const Duration(hours: 4)),
    BunkShift.p1LateRest => (midpoint, const Duration(hours: 3, minutes: 30)),
    BunkShift.cabinFirst => (cruiseStart, const Duration(hours: 3)),
    BunkShift.cabinSecond => (
      cruiseStart.add(const Duration(hours: 4)),
      const Duration(hours: 3),
    ),
  };

  var sleepEnd = sleepStart.add(sleepLength);
  if (sleepEnd.isAfter(cruiseEnd)) sleepEnd = cruiseEnd;
  if (!sleepEnd.isAfter(sleepStart)) {
    sleepEnd = sleepStart.add(const Duration(minutes: 30));
  }
  return (startUtc: sleepStart, endUtc: sleepEnd);
}

/// In-flight rest cues for one bunk slot. Times hang off STD and block.
List<BunkCue> buildBunkPlan(JetlagScheduleSnapshot schedule, BunkShift shift) {
  final rest = bunkAssignedRest(schedule, shift);
  final sleepStart = rest.startUtc;
  final sleepEnd = rest.endUtc;
  final cutoff = sleepStart.subtract(const Duration(hours: 4));

  TripleClockText clocks(DateTime start, DateTime? end) {
    return formatTripleClock(
      startUtc: start,
      endUtc: end,
      localIana: schedule.localTimeZone,
      localTag: schedule.stationLabel,
      homeIana: schedule.referenceTimeZone,
    );
  }

  final caffeine = clocks(cutoff, null);
  final sleep = clocks(sleepStart, sleepEnd);
  final wake = clocks(sleepEnd, null);

  return [
    BunkCue(
      kind: BunkCueKind.caffeine,
      title: '카페인 제한',
      window: caffeine.local.replaceFirst(' (', ' 이후 ('),
      supporting: caffeine.supporting,
      detail: '벙크 수면 4시간 전부터 카페인을 피합니다.',
    ),
    BunkCue(
      kind: BunkCueKind.sleep,
      title: '수면 구간',
      window: sleep.local,
      supporting: sleep.supporting,
      detail: '눈가리개와 귀마개로 이 구간에 수면합니다.',
    ),
    BunkCue(
      kind: BunkCueKind.wake,
      title: '기상·각성',
      window: wake.local,
      supporting: wake.supporting,
      detail: '기상 후 밝은 빛으로 각성합니다.',
    ),
  ];
}

/// Assigned bunk rest ∩ the same body-clock night [inflightRestWindow] uses.
class BunkBodyClockOverlap {
  const BunkBodyClockOverlap({
    required this.overlap,
    required this.lineStartUtc,
    required this.lineEndUtc,
    required this.missedNight,
    required this.shortOverlap,
    required this.headline,
    required this.supplement,
    required this.nightBedUtc,
    required this.nightWakeUtc,
  });

  final Duration overlap;

  /// Overlap span, or the full night when there is no overlap.
  final DateTime lineStartUtc;
  final DateTime lineEndUtc;

  final bool missedNight;
  final bool shortOverlap;
  final String headline;
  final String supplement;
  final DateTime nightBedUtc;
  final DateTime nightWakeUtc;
}

/// Overlap of the chosen bunk slot with the flight's body-clock night.
///
/// The night is the full bed–wake that [inflightRestWindow] picks (not the
/// cruise-clipped reference window). P1 and P2 share that night.
BunkBodyClockOverlap? bunkBodyClockOverlap({
  required JetlagScheduleSnapshot schedule,
  required BunkShift shift,
  required JetlagLifestyle lifestyle,
  UserSettings settings = UserSettings.defaults,
  String? originZone,
  String? destinationZone,
  String? homeZone,
}) {
  final std = schedule.stdUtc.toUtc();
  final block = schedule.blockMinutes;
  if (block <= 0) return null;
  final sta = std.add(Duration(minutes: block));
  if (!sta.isAfter(std)) return null;

  final home = homeZone ?? schedule.referenceTimeZone;
  final origin = originZone ?? schedule.localTimeZone;
  final destination = destinationZone ?? schedule.referenceTimeZone;

  final night = bodyClockNightForFlight(
    stdUtc: std,
    staUtc: sta,
    originZone: origin,
    destinationZone: destination,
    homeZone: home,
    lifestyle: lifestyle,
    settings: settings,
  );
  if (night == null) return null;

  final rest = bunkAssignedRest(schedule, shift);
  final overlap = _overlapDuration(
    rest.startUtc,
    rest.endUtc,
    night.bedUtc,
    night.wakeUtc,
  );
  final missed = overlap == Duration.zero;
  final short = overlap > Duration.zero && overlap < kSleepCycle;
  final span = missed
      ? (start: night.bedUtc, end: night.wakeUtc)
      : _clipped(
          rest.startUtc,
          rest.endUtc,
          night.bedUtc,
          night.wakeUtc,
        );

  final cycleMinutes = kSleepCycle.inMinutes;
  final topUp =
      '실제 휴식은 크루 배정에 따르고, 컨디션에 맞춰 $cycleMinutes'
      '분 이내로 잠을 보충해 보세요.';
  const insideNight =
      '이 배정 구간은 생체시계 밤에 들어가 있어요. 실제 휴식은 크루 배정에 따릅니다.';

  final String headline;
  final String supplement;
  if (missed) {
    headline = '생체시계 밤과 겹치지 않아요';
    supplement = topUp;
  } else if (short) {
    headline = '짧게 겹쳐요';
    supplement = topUp;
  } else {
    headline = '배정 휴식이 생체시계 밤과 ${_durationLabel(overlap)} 겹쳐요';
    supplement = insideNight;
  }

  return BunkBodyClockOverlap(
    overlap: overlap,
    lineStartUtc: span.start,
    lineEndUtc: span.end,
    missedNight: missed,
    shortOverlap: short,
    headline: headline,
    supplement: supplement,
    nightBedUtc: night.bedUtc,
    nightWakeUtc: night.wakeUtc,
  );
}

/// Dual-zone gray line under the bunk body-clock headline. No UTC(Z).
String bunkBodyClockLine({
  required BunkBodyClockOverlap overlap,
  required String localIana,
  required String localTag,
  required String homeIana,
}) {
  final localRange =
      '${formatHm(overlap.lineStartUtc, localIana)}–'
      '${formatHm(overlap.lineEndUtc, localIana)}';
  final homeRange =
      '${formatHm(overlap.lineStartUtc, homeIana)}–'
      '${formatHm(overlap.lineEndUtc, homeIana)}';
  final abbr = zoneAbbreviation(overlap.lineStartUtc.toUtc(), homeIana);
  final label = overlap.missedNight ? '생체시계 밤' : '겹치는 시간';
  return '$label $localRange ($localTag) · $homeRange $abbr';
}

Duration _overlapDuration(
  DateTime a0,
  DateTime a1,
  DateTime b0,
  DateTime b1,
) {
  final start = a0.isAfter(b0) ? a0 : b0;
  final end = a1.isBefore(b1) ? a1 : b1;
  if (!end.isAfter(start)) return Duration.zero;
  return end.difference(start);
}

({DateTime start, DateTime end}) _clipped(
  DateTime a0,
  DateTime a1,
  DateTime b0,
  DateTime b1,
) {
  final start = a0.isAfter(b0) ? a0 : b0;
  final end = a1.isBefore(b1) ? a1 : b1;
  return (start: start, end: end);
}

String _durationLabel(Duration duration) {
  final minutes = duration.inMinutes.abs();
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '$mins분';
  if (mins == 0) return '$hours시간';
  return '$hours시간 $mins분';
}
