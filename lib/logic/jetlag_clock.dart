import 'package:timezone/data/latest_all.dart' as tzdata;
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

/// Hour and minute of an absolute instant on the UTC clock (digits only).
String formatUtcHm(DateTime instant) {
  final utc = instant.toUtc();
  final hour = utc.hour.toString().padLeft(2, '0');
  final minute = utc.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Single UTC clock with a trailing Z, for example `13:30Z`.
///
/// Does not append another Z when [formatUtcHm] already ends with one.
String formatUtcClock(DateTime instant) {
  final hm = formatUtcHm(instant);
  return hm.endsWith('Z') ? hm : '${hm}Z';
}

/// UTC span with Z on both ends, for example `08:35Z - 15:35Z`.
String formatUtcSpan(DateTime startUtc, DateTime? endUtc) {
  final start = formatUtcClock(startUtc);
  if (endUtc == null) return start;
  return '$start - ${formatUtcClock(endUtc)}';
}

String _span(
  DateTime startUtc,
  DateTime? endUtc,
  String Function(DateTime) one,
) {
  final start = one(startUtc.toUtc());
  if (endUtc == null) return start;
  return '$start - ${one(endUtc.toUtc())}';
}

bool _isUtcZone(String iana) {
  final id = iana.trim();
  return id == 'UTC' || id == 'Etc/UTC';
}

/// Local wall time as the primary line, with home base and UTC underneath.
///
/// Rendering is the only place a zone offset is applied. [startUtc] and
/// [endUtc] are absolute instants and are converted with [toUtc] first.
class TripleClockText {
  const TripleClockText({required this.local, required this.supporting});

  final String local;
  final String supporting;
}

TripleClockText formatTripleClock({
  required DateTime startUtc,
  DateTime? endUtc,
  required String localIana,
  required String localTag,
  required String homeIana,
}) {
  final localSpan = _span(startUtc, endUtc, (utc) => formatHm(utc, localIana));
  final homeSpan = _span(startUtc, endUtc, (utc) => formatHm(utc, homeIana));
  final utcSpan = formatUtcSpan(startUtc, endUtc);
  final homeAbbr = zoneAbbreviation(startUtc.toUtc(), homeIana);
  return TripleClockText(
    local: '$localSpan ($localTag)',
    supporting: '$homeSpan $homeAbbr · $utcSpan',
  );
}

/// Cockpit strip: `07:51 LAX (Local)  |  00:51 KST (Home)  |  15:51Z (UTC)`.
String formatCockpitLine({
  required DateTime nowUtc,
  required String localIana,
  required String homeIana,
  required String stationLabel,
}) {
  final utc = nowUtc.toUtc();
  final local = '${formatHm(utc, localIana)} $stationLabel (Local)';
  final home =
      '${formatHm(utc, homeIana)} ${zoneAbbreviation(utc, homeIana)} (Home)';
  final zulu = '${formatUtcClock(utc)} (UTC)';
  return '$local  |  $home  |  $zulu';
}

/// Home-base wall time and the UTC clock for one instant.
String formatHomeAndUtc(DateTime instant, String homeIana) {
  final utc = instant.toUtc();
  final home = formatHm(utc, homeIana);
  final abbr = zoneAbbreviation(utc, homeIana);
  return '$home $abbr · ${formatUtcClock(utc)}';
}

/// Home-base span only, for example `17:35 - 00:35 KST`.
/// Used on planned-sleep cards so the alarm home clock can share the row.
String formatHomeSpan(DateTime startUtc, DateTime? endUtc, String homeIana) {
  final homeSpan = _span(startUtc, endUtc, (utc) => formatHm(utc, homeIana));
  final homeAbbr = zoneAbbreviation(startUtc.toUtc(), homeIana);
  return '$homeSpan $homeAbbr';
}

/// Local wake for the sleep-card alarm, for example `16:35 (AMS)`.
String formatAlarmLocal(DateTime wakeUtc, String localIana, String localTag) {
  return '${formatHm(wakeUtc, localIana)} ($localTag)';
}

/// Home wake for the sleep-card alarm, for example `00:35 KST`.
String formatAlarmHome(DateTime wakeUtc, String homeIana) {
  final utc = wakeUtc.toUtc();
  return '${formatHm(utc, homeIana)} ${zoneAbbreviation(utc, homeIana)}';
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
  if (_isUtcZone(iana)) {
    final start = formatUtcClock(startUtc);
    if (endUtc == null) return start;
    return '$start–${formatUtcClock(endUtc)}';
  }
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
