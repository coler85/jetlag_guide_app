import 'jetlag_clock.dart';

/// Latest [hour]:[minute] in [iana] that is not after [nowUtc].
DateTime mostRecentWallClock({
  required DateTime nowUtc,
  required String iana,
  required int hour,
  required int minute,
}) {
  final today = atWallTime(
    dayAnchorUtc: nowUtc,
    iana: iana,
    hour: hour,
    minute: minute,
  );
  if (!today.isAfter(nowUtc.toUtc())) return today;
  final wall = wallClock(nowUtc, iana);
  final previous = DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
  ).subtract(const Duration(days: 1));
  return zonedUtc(
    iana: iana,
    year: previous.year,
    month: previous.month,
    day: previous.day,
    hour: hour,
    minute: minute,
  );
}

/// Bed and wake instants for one entered sleep.
///
/// Without [pinnedDay], the bed clock is its latest occurrence and the wake
/// clock is the same night. A wake that would fall after [nowUtc] moves both
/// edges one calendar day earlier. A day the crew picked is left as entered.
({DateTime startUtc, DateTime endUtc}) resolveSleepInterval({
  required DateTime nowUtc,
  required String iana,
  required int bedHour,
  required int bedMinute,
  required int wakeHour,
  required int wakeMinute,
  DateTime? pinnedDay,
}) {
  final now = nowUtc.toUtc();
  final DateTime bed;
  if (pinnedDay != null) {
    bed = zonedUtc(
      iana: iana,
      year: pinnedDay.year,
      month: pinnedDay.month,
      day: pinnedDay.day,
      hour: bedHour,
      minute: bedMinute,
    );
  } else {
    bed = mostRecentWallClock(
      nowUtc: now,
      iana: iana,
      hour: bedHour,
      minute: bedMinute,
    );
  }
  var start = bed;
  var end = wakeAfterBed(
    bedUtc: bed,
    iana: iana,
    hour: wakeHour,
    minute: wakeMinute,
  );
  if (pinnedDay == null && end.isAfter(now)) {
    start = _shiftWallDay(start, iana, -1);
    end = _shiftWallDay(end, iana, -1);
  }
  return (startUtc: start, endUtc: end);
}

DateTime _shiftWallDay(DateTime utc, String iana, int days) {
  final wall = wallClock(utc, iana);
  final day = DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
  ).add(Duration(days: days));
  return zonedUtc(
    iana: iana,
    year: day.year,
    month: day.month,
    day: day.day,
    hour: wall.hour,
    minute: wall.minute,
  );
}

/// Wake on the bed's calendar day, or the next day when the wake clock is earlier.
DateTime wakeAfterBed({
  required DateTime bedUtc,
  required String iana,
  required int hour,
  required int minute,
}) {
  final bed = wallClock(bedUtc, iana);
  final bedMinutes = bed.hour * 60 + bed.minute;
  final wakeMinutes = hour * 60 + minute;
  final day = DateTime.utc(bed.year, bed.month, bed.day);
  final wakeDay = wakeMinutes < bedMinutes
      ? day.add(const Duration(days: 1))
      : day;
  return zonedUtc(
    iana: iana,
    year: wakeDay.year,
    month: wakeDay.month,
    day: wakeDay.day,
    hour: hour,
    minute: minute,
  );
}
