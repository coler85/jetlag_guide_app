import '../models/crew_log.dart';
import '../models/guide_event.dart';
import '../models/jetlag_schedule.dart';
import '../models/lifestyle.dart';
import '../models/sleep_log.dart';
import '../models/user_settings.dart';
import 'jetlag_clock.dart';
import 'lifestyle_plan.dart';

class JetlagDashboard {
  const JetlagDashboard({
    required this.sleeping,
    required this.stateLabel,
    required this.cueLabel,
    required this.cueClock,
    required this.cueZone,
    required this.pickupMissing,
    required this.pickupClock,
    required this.pickupZone,
    required this.dday,
    required this.remaining,
    this.sleepDebtLabel = '0분',
    this.sleepDebtInDebt = false,
  });

  final bool sleeping;
  final String stateLabel;

  /// Subtitle under the current state. Awake shows the next sleep or the
  /// caffeine cutoff. A recommended sleep shows the suggested wake time.
  final String cueLabel;
  final String cueClock;
  final String cueZone;
  final bool pickupMissing;
  final String pickupClock;
  final String pickupZone;
  final String dday;
  final String remaining;

  /// Signed balance against the usual night. Negative is a debt.
  final String sleepDebtLabel;
  final bool sleepDebtInDebt;
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

  /// True when this date owns a guide event or a crew log.
  /// A now-line by itself is not a date group.
  bool get hasDatedContent =>
      markers.any((marker) => marker is EventMarker || marker is LogMarker);
}

List<GuideEvent> buildGuideEvents(
  JetlagScheduleSnapshot schedule, {
  JetlagLifestyle lifestyle = JetlagLifestyle.kstAnchor,
  UserSettings settings = UserSettings.defaults,
  List<SleepLog> sleepLogs = const [],
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
    ...lifestyleBlocks(
      schedule: schedule,
      lifestyle: lifestyle,
      settings: settings,
    ),
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
  for (final log in sleepLogs) {
    if (!log.isValid) continue;
    events.add(
      GuideEvent(
        id: 'logged-sleep-${log.id}',
        kind: GuideEventKind.sleep,
        startUtc: log.startUtc,
        endUtc: log.endUtc,
        title: '기록한 수면',
        detail: '입력한 수면 시간입니다.',
      ),
    );
  }
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
  final nowUtc = instant.toUtc();
  for (final event in events) {
    final end = event.endUtc?.toUtc();
    if (event.kind != GuideEventKind.sleep || end == null) continue;
    if (!event.startUtc.toUtc().isAfter(nowUtc) && end.isAfter(nowUtc)) {
      return event;
    }
  }
  return null;
}

bool isSleeping({
  required List<GuideEvent> events,
  required List<CrewLog> logs,
  required DateTime now,
  List<SleepLog> sleepLogs = const [],
}) {
  final nowUtc = now.toUtc();
  if (sleepLogs.any((log) => log.covers(nowUtc))) return true;
  if (openSleepLog(logs) != null) return true;
  final planned = _coveringSleep(events, nowUtc);
  if (planned == null) return false;
  final woke = logs.any(
    (log) =>
        log.kind == CrewLogKind.wake &&
        !log.atUtc.toUtc().isBefore(planned.startUtc.toUtc()),
  );
  return !woke;
}

DateTime? recommendedWake({
  required List<GuideEvent> events,
  required List<CrewLog> logs,
  required DateTime now,
}) {
  final nowUtc = now.toUtc();
  final open = openSleepLog(logs);
  if (open != null) {
    final covering = _coveringSleep(events, open.atUtc.toUtc());
    if (covering?.endUtc != null) return covering!.endUtc!.toUtc();
    return open.atUtc.toUtc().add(const Duration(hours: 8));
  }
  final current = _coveringSleep(events, nowUtc);
  if (current?.endUtc != null) return current!.endUtc!.toUtc();
  for (final event in events) {
    final end = event.endUtc?.toUtc();
    if (event.kind == GuideEventKind.sleep &&
        end != null &&
        end.isAfter(nowUtc)) {
      return end;
    }
  }
  return null;
}

DateTime? _nextKind(
  List<GuideEvent> events,
  DateTime nowUtc,
  GuideEventKind kind,
) {
  DateTime? best;
  for (final event in events) {
    if (event.kind != kind || event.missing) continue;
    final start = event.startUtc.toUtc();
    if (!start.isAfter(nowUtc)) continue;
    if (best == null || start.isBefore(best)) best = start;
  }
  return best;
}

/// While awake, the nearer of the next caffeine cutoff and the next bedtime.
({String label, DateTime? instant}) awakeCue(
  List<GuideEvent> events,
  DateTime now,
) {
  final nowUtc = now.toUtc();
  final sleep = _nextKind(events, nowUtc, GuideEventKind.sleep);
  final caffeine = _nextKind(events, nowUtc, GuideEventKind.caffeine);
  if (caffeine != null && (sleep == null || !caffeine.isAfter(sleep))) {
    return (label: '카페인 컷오프', instant: caffeine);
  }
  return (label: '다음 권장 취침', instant: sleep);
}

JetlagDashboard buildDashboard({
  required JetlagScheduleSnapshot schedule,
  required List<GuideEvent> events,
  required List<CrewLog> logs,
  required DateTime now,
  List<SleepLog> sleepLogs = const [],
  String sleepDebtLabel = '0분',
  bool sleepDebtInDebt = false,
}) {
  final nowUtc = now.toUtc();
  final sleeping = isSleeping(
    events: events,
    logs: logs,
    now: nowUtc,
    sleepLogs: sleepLogs,
  );
  final local = schedule.localTimeZone;
  final home = schedule.referenceTimeZone;
  final pickup = schedule.pickupUtc?.toUtc();
  String state = '활동 중';
  late final String cueLabel;
  late final DateTime? cueInstant;
  final coveringLog = _coveringSleepLog(sleepLogs, nowUtc);
  if (sleeping) {
    state = openSleepLog(logs) != null || coveringLog != null
        ? '수면 중'
        : '수면 권장';
    cueLabel = '권장 기상';
    cueInstant =
        coveringLog?.endUtc ??
        recommendedWake(events: events, logs: logs, now: nowUtc);
  } else {
    for (final event in events) {
      final end = event.endUtc;
      if (end == null || event.missing) continue;
      if (!event.startUtc.toUtc().isAfter(nowUtc) &&
          end.toUtc().isAfter(nowUtc)) {
        state = event.title;
        break;
      }
    }
    final cue = awakeCue(events, nowUtc);
    cueLabel = cue.label;
    cueInstant = cue.instant;
  }

  return JetlagDashboard(
    sleeping: sleeping,
    stateLabel: state,
    cueLabel: cueLabel,
    cueClock: cueInstant == null ? '—' : formatHm(cueInstant, local),
    cueZone: cueInstant == null
        ? (sleeping ? '권장 시각 없음' : '예정 없음')
        : formatHomeAndUtc(cueInstant, home),
    pickupMissing: pickup == null,
    pickupClock: pickup == null ? '미입력' : formatHm(pickup, local),
    pickupZone: pickup == null
        ? schedule.stationLabel
        : _dualZone(pickup, schedule),
    dday: pickup == null
        ? 'D—'
        : ddayLabel(calendarDelta(fromUtc: nowUtc, toUtc: pickup, iana: local)),
    remaining: pickup == null ? '시간 미정' : formatLead(pickup.difference(nowUtc)),
    sleepDebtLabel: sleepDebtLabel,
    sleepDebtInDebt: sleepDebtInDebt,
  );
}

SleepLog? _coveringSleepLog(List<SleepLog> logs, DateTime nowUtc) {
  for (final log in logs) {
    if (log.covers(nowUtc)) return log;
  }
  return null;
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

int _markerRank(TimelineMarker marker) {
  return switch (marker) {
    EventMarker() => 0,
    LogMarker() => 1,
    BunkMarker() => 2,
    NowMarker() => 3,
  };
}

bool _eventDimmed(GuideEvent event, DateTime nowUtc) {
  if (event.missing) return false;
  final end = (event.endUtc ?? event.startUtc).toUtc();
  return !end.isAfter(nowUtc);
}

List<TimelineSection> buildTimelineSections({
  required JetlagScheduleSnapshot schedule,
  required List<CrewLog> logs,
  required DateTime now,
  JetlagLifestyle lifestyle = JetlagLifestyle.kstAnchor,
  UserSettings settings = UserSettings.defaults,
  List<SleepLog> sleepLogs = const [],
}) {
  final nowUtc = now.toUtc();
  final events = buildGuideEvents(
    schedule,
    lifestyle: lifestyle,
    settings: settings,
    sleepLogs: sleepLogs,
  );
  final zone = schedule.localTimeZone;
  final markers = <TimelineMarker>[];

  for (final event in events) {
    final start = event.startUtc.toUtc();
    markers.add(
      EventMarker(
        event: event,
        dimmed: _eventDimmed(event, nowUtc),
        dayKey: dayKey(start, zone),
      ),
    );
  }
  for (final log in logs) {
    final at = log.atUtc.toUtc();
    markers.add(
      LogMarker(
        log: log,
        dimmed: at.isBefore(nowUtc),
        dayKey: dayKey(at, zone),
      ),
    );
  }
  markers.sort((a, b) {
    final byTime = a.stamp.toUtc().compareTo(b.stamp.toUtc());
    if (byTime != 0) return byTime;
    return _markerRank(a).compareTo(_markerRank(b));
  });

  final laid = <TimelineMarker>[];
  for (final marker in markers) {
    laid.add(marker);
    if (marker is EventMarker && marker.event.kind == GuideEventKind.pickup) {
      laid.add(BunkMarker(stamp: marker.stamp.toUtc(), dayKey: marker.dayKey));
    }
  }

  final nowMarker = NowMarker(stamp: nowUtc, dayKey: dayKey(nowUtc, zone));
  final insertAt = laid.indexWhere(
    (marker) => marker.stamp.toUtc().isAfter(nowUtc),
  );
  if (insertAt < 0) {
    laid.add(nowMarker);
  } else {
    laid.insert(insertAt, nowMarker);
  }

  final sections = <TimelineSection>[];
  for (final marker in laid) {
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
  return _withoutEmptyDateGroups(sections);
}

/// Drops a date whose markers contain no event and no log.
/// A now-line from that date is kept on the neighboring group that has content.
List<TimelineSection> _withoutEmptyDateGroups(List<TimelineSection> sections) {
  final kept = <TimelineSection>[];
  final displaced = <NowMarker>[];
  for (final section in sections) {
    if (!section.hasDatedContent) {
      displaced.addAll(section.markers.whereType<NowMarker>());
      continue;
    }
    if (displaced.isNotEmpty) {
      section.markers.insertAll(0, displaced);
      displaced.clear();
    }
    kept.add(section);
  }
  if (displaced.isEmpty) return kept;
  if (kept.isEmpty) {
    return [
      TimelineSection(
        dayKey: displaced.first.dayKey,
        heading: '',
        markers: displaced,
      ),
    ];
  }
  kept.last.markers.addAll(displaced);
  return kept;
}
