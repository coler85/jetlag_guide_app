import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _zonesReady = false;

void ensureJetlagTimeZones() {
  if (_zonesReady) return;
  try {
    tz.getLocation('Asia/Seoul');
    _zonesReady = true;
  } catch (_) {
    tzdata.initializeTimeZones();
    _zonesReady = true;
  }
}

tz.TZDateTime wallClock(DateTime utc, String iana) {
  ensureJetlagTimeZones();
  return tz.TZDateTime.from(utc.toUtc(), tz.getLocation(iana));
}

String formatHm(DateTime utc, String iana) {
  final wall = wallClock(utc, iana);
  final hour = wall.hour.toString().padLeft(2, '0');
  final minute = wall.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Abbreviation reported by the timezone database at [utc].
/// Falls back to the city segment of [iana] when the lookup fails.
String zoneAbbreviation(DateTime utc, String iana) {
  try {
    final name = wallClock(utc, iana).timeZoneName.trim();
    if (name.isNotEmpty) return name;
  } catch (_) {}
  final slash = iana.lastIndexOf('/');
  final tail = slash >= 0 ? iana.substring(slash + 1) : iana;
  final cleaned = tail.replaceAll('_', ' ').trim();
  return cleaned.isEmpty ? iana : cleaned;
}

String formatRange(DateTime startUtc, DateTime? endUtc, String iana) {
  final start = formatHm(startUtc, iana);
  if (endUtc == null) return start;
  return '$start–${formatHm(endUtc, iana)}';
}

String dayKey(DateTime utc, String iana) {
  final wall = wallClock(utc, iana);
  return '${wall.year}-${wall.month.toString().padLeft(2, '0')}-${wall.day.toString().padLeft(2, '0')}';
}

String dayHeading(DateTime utc, String iana, String station) {
  final wall = wallClock(utc, iana);
  const names = ['월', '화', '수', '목', '금', '토', '일'];
  return '${wall.month}월 ${wall.day}일 (${names[wall.weekday - 1]}) · $station';
}

/// Same calendar date as [dayAnchorUtc] in [iana], with a new clock time.
DateTime atWallTime({
  required DateTime dayAnchorUtc,
  required String iana,
  required int hour,
  required int minute,
}) {
  ensureJetlagTimeZones();
  final wall = wallClock(dayAnchorUtc, iana);
  return tz.TZDateTime(
    tz.getLocation(iana),
    wall.year,
    wall.month,
    wall.day,
    hour,
    minute,
  ).toUtc();
}

int calendarDelta({
  required DateTime fromUtc,
  required DateTime toUtc,
  required String iana,
}) {
  final from = wallClock(fromUtc, iana);
  final to = wallClock(toUtc, iana);
  final start = DateTime.utc(from.year, from.month, from.day);
  final end = DateTime.utc(to.year, to.month, to.day);
  return end.difference(start).inDays;
}

String ddayLabel(int delta) {
  if (delta == 0) return 'D-Day';
  if (delta > 0) return 'D-$delta';
  return 'D+${-delta}';
}

DateTime zonedUtc({
  required String iana,
  required int year,
  required int month,
  required int day,
  required int hour,
  required int minute,
  Duration shift = Duration.zero,
}) {
  ensureJetlagTimeZones();
  final wall = tz.TZDateTime(
    tz.getLocation(iana),
    year,
    month,
    day,
    hour,
    minute,
  );
  return wall.add(shift).toUtc();
}

/// Local UTC offset minus the home UTC offset at [utc].
Duration zoneOffset(DateTime utc, String localIana, String homeIana) {
  return wallClock(utc, localIana).timeZoneOffset -
      wallClock(utc, homeIana).timeZoneOffset;
}

List<DateTime> calendarDays(String iana, DateTime startUtc, DateTime endUtc) {
  final start = wallClock(startUtc, iana);
  final end = wallClock(endUtc, iana);
  final days = <DateTime>[];
  var cursor = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  while (!cursor.isAfter(last)) {
    days.add(cursor);
    cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
  }
  return days;
}

String formatLead(Duration duration) {
  final negative = duration.isNegative;
  final minutes = duration.abs().inMinutes;
  final days = minutes ~/ (60 * 24);
  final hours = (minutes % (60 * 24)) ~/ 60;
  final mins = minutes % 60;
  final parts = <String>[
    if (days > 0) '$days일',
    if (hours > 0) '$hours시간',
    if (mins > 0 || (days == 0 && hours == 0)) '$mins분',
  ];
  final text = parts.join(' ');
  return negative ? '$text 지남' : '$text 남음';
}
