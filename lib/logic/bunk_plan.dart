import '../models/bunk_shift.dart';
import '../models/jetlag_schedule.dart';
import 'jetlag_clock.dart';

/// In-flight rest cues for one bunk slot. Times hang off STD and block.
List<BunkCue> buildBunkPlan(JetlagScheduleSnapshot schedule, BunkShift shift) {
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
