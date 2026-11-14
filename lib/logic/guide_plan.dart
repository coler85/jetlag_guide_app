import '../models/crew_log.dart';
import '../models/guide_event.dart';
import '../models/jetlag_schedule.dart';
import '../models/lifestyle.dart';
import 'jetlag_clock.dart';
import 'lifestyle_plan.dart';

class JetlagDashboard {
  const JetlagDashboard({
    required this.sleeping,
    required this.stateLabel,
    required this.wakeClock,
    required this.wakeZone,
    required this.pickupMissing,
    required this.pickupClock,
    required this.pickupZone,
    required this.dday,
    required this.remaining,
  });

  final bool sleeping;
  final String stateLabel;
  final String wakeClock;
  final String wakeZone;
  final bool pickupMissing;
  final String pickupClock;
  final String pickupZone;
  final String dday;
  final String remaining;
}

sealed class TimelineMarker {
  DateTime get stamp;
  String get dayKey;
}

class EventMarker extends TimelineMarker {
  EventMarker({
    required this.event,
    required this.dimmed,
    required this.dayKey,
  });

  final GuideEvent event;
  final bool dimmed;

  @override
  final String dayKey;

  @override
  DateTime get stamp => event.startUtc;
}

class LogMarker extends TimelineMarker {
  LogMarker({required this.log, required this.dimmed, required this.dayKey});

  final CrewLog log;
  final bool dimmed;

  @override
  final String dayKey;

  @override
  DateTime get stamp => log.atUtc;
}

class NowMarker extends TimelineMarker {
  NowMarker({required this.stamp, required this.dayKey});

  @override
  final DateTime stamp;

  @override
  final String dayKey;
}

class BunkMarker extends TimelineMarker {
  BunkMarker({required this.stamp, required this.dayKey});

  @override
  final DateTime stamp;

  @override
  final String dayKey;
}

class TimelineSection {
  TimelineSection({
    required this.dayKey,
    required this.heading,
    required this.markers,
  });

  final String dayKey;
  final String heading;
  final List<TimelineMarker> markers;
}

List<GuideEvent> buildGuideEvents(
  JetlagScheduleSnapshot schedule, {
  JetlagLifestyle lifestyle = JetlagLifestyle.kstAnchor,
}) {
  final sta = schedule.staUtc.toUtc();
  final std = schedule.stdUtc.toUtc();
  final flight = schedule.flightNumber.trim();
  final arrivalDetail = flight.isEmpty
      ? '${schedule.stationLabel} 도착'
      : '$flight · ${schedule.stationLabel} 도착';
  if (!std.isAfter(sta)) {
    return [
      GuideEvent(
        id: 'arrival',
        kind: GuideEventKind.arrival,
        startUtc: sta,
        title: '도착',
        detail: arrivalDetail,
      ),
      GuideEvent(
        id: 'departure',
        kind: GuideEventKind.departure,
        startUtc: std,
        title: '출발',
        detail: flight.isEmpty ? '출발' : '$flight 출발',
      ),
    ];
  }

  final pickup = schedule.pickupUtc?.toUtc();
  final anchor = pickup ?? std.subtract(const Duration(hours: 3));

  final events = <GuideEvent>[
    GuideEvent(
      id: 'arrival',
      kind: GuideEventKind.arrival,
      startUtc: sta,
      title: '도착',
      detail: arrivalDetail,
    ),
    ...lifestyleBlocks(schedule: schedule, lifestyle: lifestyle),
    if (pickup != null)
      GuideEvent(
        id: 'pickup',
        kind: GuideEventKind.pickup,
        startUtc: pickup,
        title: '픽업',
        detail: '호텔 픽업.',
      )
    else
      GuideEvent(
        id: 'pickup',
        kind: GuideEventKind.pickup,
        startUtc: anchor,
        title: '픽업',
        detail: '픽업 시간 미입력',
        missing: true,
      ),
    if (schedule.showupUtc != null)
      GuideEvent(
        id: 'showup',
        kind: GuideEventKind.showup,
        startUtc: schedule.showupUtc!.toUtc(),
        title: '쇼업',
        detail: '신고 시각.',
      ),
    GuideEvent(
      id: 'departure',
      kind: GuideEventKind.departure,
      startUtc: std,
      title: '출발',
      detail: flight.isEmpty ? '출발' : '$flight 출발',
    ),
  ];

  events.removeWhere((event) {
    if (event.kind == GuideEventKind.arrival ||
        event.kind == GuideEventKind.pickup ||
        event.kind == GuideEventKind.showup ||
        event.kind == GuideEventKind.departure) {
      return false;
    }
    if (!event.startUtc.isBefore(std)) return true;
    return false;
  });
  events.sort((a, b) => a.startUtc.compareTo(b.startUtc));
  return events;
}

CrewLog? openSleepLog(List<CrewLog> logs) {
  final ordered = [...logs]..sort((a, b) => a.atUtc.compareTo(b.atUtc));
  CrewLog? open;
  for (final log in ordered) {
    if (log.kind == CrewLogKind.sleep) open = log;
    if (log.kind == CrewLogKind.wake) open = null;
  }
  return open;
}

GuideEvent? _coveringSleep(List<GuideEvent> events, DateTime instant) {
  for (final event in events) {
    final end = event.endUtc;
    if (event.kind != GuideEventKind.sleep || end == null) continue;
    if (!event.startUtc.isAfter(instant) && end.isAfter(instant)) return event;
  }
  return null;
}

bool isSleeping({
  required List<GuideEvent> events,
  required List<CrewLog> logs,
  required DateTime now,
}) {
  if (openSleepLog(logs) != null) return true;
  final planned = _coveringSleep(events, now);
  if (planned == null) return false;
  final woke = logs.any(
    (log) =>
        log.kind == CrewLogKind.wake && !log.atUtc.isBefore(planned.startUtc),
  );
  return !woke;
}

DateTime? recommendedWake({
  required List<GuideEvent> events,
  required List<CrewLog> logs,
  required DateTime now,
}) {
  final open = openSleepLog(logs);
  if (open != null) {
    final covering = _coveringSleep(events, open.atUtc);
    if (covering?.endUtc != null) return covering!.endUtc;
    return open.atUtc.add(const Duration(hours: 8));
  }
  final current = _coveringSleep(events, now);
  if (current?.endUtc != null) return current!.endUtc;
  for (final event in events) {
    final end = event.endUtc;
    if (event.kind == GuideEventKind.sleep && end != null && end.isAfter(now)) {
      return end;
    }
  }
  return null;
}

JetlagDashboard buildDashboard({
  required JetlagScheduleSnapshot schedule,
  required List<GuideEvent> events,
  required List<CrewLog> logs,
  required DateTime now,
}) {
  final sleeping = isSleeping(events: events, logs: logs, now: now);
  final wake = recommendedWake(events: events, logs: logs, now: now);
  final local = schedule.localTimeZone;
  final home = schedule.referenceTimeZone;
  final pickup = schedule.pickupUtc?.toUtc();
  String state = '활동 중';
  if (sleeping) {
    state = '수면 중';
  } else {
    for (final event in events) {
      final end = event.endUtc;
      if (end == null || event.missing) continue;
      if (!event.startUtc.isAfter(now) && end.isAfter(now)) {
        state = event.title;
        break;
      }
    }
  }

  return JetlagDashboard(
    sleeping: sleeping,
    stateLabel: state,
    wakeClock: wake == null ? '—' : formatHm(wake, home),
    wakeZone: wake == null
        ? '권장 시각 없음'
        : _dualZone(wake, schedule, primaryHome: true),
    pickupMissing: pickup == null,
    pickupClock: pickup == null ? '미입력' : formatHm(pickup, local),
    pickupZone: pickup == null
        ? schedule.stationLabel
        : _dualZone(pickup, schedule),
    dday: pickup == null
        ? 'D—'
        : ddayLabel(calendarDelta(fromUtc: now, toUtc: pickup, iana: local)),
    remaining: pickup == null ? '시간 미정' : formatLead(pickup.difference(now)),
  );
}

String _dualZone(
  DateTime utc,
  JetlagScheduleSnapshot schedule, {
  bool primaryHome = false,
}) {
  final local =
      '${formatHm(utc, schedule.localTimeZone)} ${schedule.stationLabel}';
  final home =
      '${formatHm(utc, schedule.referenceTimeZone)} ${zoneAbbreviation(utc, schedule.referenceTimeZone)}';
  if (schedule.localTimeZone == schedule.referenceTimeZone) return home;
  return primaryHome ? '$home · $local' : '$local · $home';
}

int _group(GuideEvent event, DateTime now) {
  if (event.missing) return 2;
  final end = event.endUtc ?? event.startUtc;
  if (!end.isAfter(now)) return 0;
  if (event.startUtc.isAfter(now)) return 2;
  return 1;
}

int _logGroup(CrewLog log, DateTime now) {
  if (log.atUtc.isBefore(now)) return 0;
  if (log.atUtc.isAfter(now)) return 2;
  return 1;
}

List<TimelineSection> buildTimelineSections({
  required JetlagScheduleSnapshot schedule,
  required List<CrewLog> logs,
  required DateTime now,
  JetlagLifestyle lifestyle = JetlagLifestyle.kstAnchor,
}) {
  final events = buildGuideEvents(schedule, lifestyle: lifestyle);
  final zone = schedule.localTimeZone;
  final timed = <({DateTime time, int group, TimelineMarker marker})>[];

  for (final event in events) {
    final group = _group(event, now);
    timed.add((
      time: event.startUtc,
      group: group,
      marker: EventMarker(
        event: event,
        dimmed: group == 0,
        dayKey: dayKey(event.startUtc, zone),
      ),
    ));
  }
  for (final log in logs) {
    final group = _logGroup(log, now);
    timed.add((
      time: log.atUtc,
      group: group,
      marker: LogMarker(
        log: log,
        dimmed: group == 0,
        dayKey: dayKey(log.atUtc, zone),
      ),
    ));
  }
  timed.sort((a, b) {
    final byGroup = a.group.compareTo(b.group);
    if (byGroup != 0) return byGroup;
    return a.time.compareTo(b.time);
  });

  final markers = <TimelineMarker>[];
  var placedNow = false;
  for (final item in timed) {
    if (!placedNow && item.group > 0) {
      markers.add(NowMarker(stamp: now, dayKey: dayKey(now, zone)));
      placedNow = true;
    }
    markers.add(item.marker);
    final marker = item.marker;
    if (marker is EventMarker && marker.event.kind == GuideEventKind.pickup) {
      markers.add(BunkMarker(stamp: marker.stamp, dayKey: marker.dayKey));
    }
  }
  if (!placedNow) {
    markers.add(NowMarker(stamp: now, dayKey: dayKey(now, zone)));
  }

  final sections = <TimelineSection>[];
  for (final marker in markers) {
    if (sections.isEmpty || sections.last.dayKey != marker.dayKey) {
      sections.add(
        TimelineSection(
          dayKey: marker.dayKey,
          heading: dayHeading(marker.stamp, zone, schedule.stationLabel),
          markers: [marker],
        ),
      );
    } else {
      sections.last.markers.add(marker);
    }
  }
  return sections;
}
