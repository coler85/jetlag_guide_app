import 'package:flutter/foundation.dart';

import '../models/crew_log.dart';
import '../models/guide_event.dart';
import '../models/jetlag_schedule.dart';
import '../models/lifestyle.dart';
import '../models/sleep_log.dart';
import '../models/user_settings.dart';
import 'guide_plan.dart';
import 'home_base_timezone.dart';
import 'home_departure.dart';
import 'sleep_debt.dart';

/// One pass of the guide timeline for a single home base.
class JetLagTimeline {
  const JetLagTimeline({
    required this.schedule,
    required this.events,
    required this.dashboard,
    required this.sections,
  });

  final JetlagScheduleSnapshot schedule;
  final List<GuideEvent> events;
  final JetlagDashboard dashboard;
  final List<TimelineSection> sections;

  /// Shown when zone math cannot run. Keeps the page from throwing.
  factory JetLagTimeline.unavailable(JetlagScheduleSnapshot schedule) {
    return JetLagTimeline(
      schedule: schedule,
      events: const [],
      dashboard: JetlagDashboard(
        sleeping: false,
        stateLabel: '활동 중',
        cueLabel: '다음 권장 취침',
        cueClock: '—',
        cueZone: '시간대를 계산하지 못했습니다',
        pickupMissing: schedule.pickupUtc == null,
        pickupClock: '—',
        pickupZone: schedule.stationLabel,
        dday: 'D—',
        remaining: '시간 미정',
      ),
      sections: const [],
    );
  }
}

/// Rebuilds sleep windows and the timeline from the selected home base.
class JetLagCalculator {
  const JetLagCalculator();

  final HomeDepartureAdvisor homeDeparture = const HomeDepartureAdvisor();
  final SleepDebtCalculator sleepDebt = const SleepDebtCalculator();

  JetLagTimeline calculate({
    required JetlagScheduleSnapshot schedule,
    required JetlagLifestyle lifestyle,
    required List<CrewLog> logs,
    required DateTime now,
    required String homeBaseTimezone,
    UserSettings settings = UserSettings.defaults,
    List<SleepLog> sleepLogs = const [],
  }) {
    final nowUtc = now.toUtc();
    final utcLogs = [
      for (final log in logs)
        CrewLog(
          id: log.id,
          atUtc: log.atUtc.toUtc(),
          kind: log.kind,
          scheduleKey: log.scheduleKey,
        ),
    ];
    try {
      return _build(
        schedule: schedule,
        lifestyle: lifestyle,
        logs: utcLogs,
        sleepLogs: sleepLogs,
        settings: settings,
        now: nowUtc,
        homeBaseTimezone: homeBaseTimezone,
      );
    } catch (error, stack) {
      debugPrint('JetLagCalculator fallback: $error\n$stack');
      try {
        return _build(
          schedule: schedule,
          lifestyle: lifestyle,
          logs: utcLogs,
          sleepLogs: sleepLogs,
          settings: settings,
          now: nowUtc,
          homeBaseTimezone: kJetlagFallbackHomeBase,
        );
      } catch (fallbackError, fallbackStack) {
        debugPrint(
          'JetLagCalculator unavailable: $fallbackError\n$fallbackStack',
        );
        return JetLagTimeline.unavailable(schedule);
      }
    }
  }

  JetLagTimeline _build({
    required JetlagScheduleSnapshot schedule,
    required JetlagLifestyle lifestyle,
    required List<CrewLog> logs,
    required List<SleepLog> sleepLogs,
    required UserSettings settings,
    required DateTime now,
    required String homeBaseTimezone,
  }) {
    final nowUtc = now.toUtc();
    final home = resolveHomeBaseTimezone(homeBaseTimezone);
    final effective = schedule.copyWith(
      staUtc: schedule.staUtc.toUtc(),
      stdUtc: schedule.stdUtc.toUtc(),
      pickupUtc: schedule.pickupUtc?.toUtc(),
      clearPickup: schedule.pickupUtc == null,
      showupUtc: schedule.showupUtc?.toUtc(),
      referenceTimeZone: home,
    );
    final normalized = settings.normalized();
    final utcSleep = [
      for (final log in sleepLogs)
        if (log.isValid)
          SleepLog(
            id: log.id,
            startUtc: log.startUtc.toUtc(),
            endUtc: log.endUtc.toUtc(),
            scheduleKey: log.scheduleKey,
          ),
    ];
    final departure = homeDeparture.evaluate(
      schedule: effective,
      settings: normalized,
    );
    final debt = sleepDebt.evaluate(
      usual: normalized.usualSleep,
      logs: utcSleep,
      departure: departure,
    );
    final events = buildGuideEvents(
      effective,
      lifestyle: lifestyle,
      settings: normalized,
      sleepLogs: utcSleep,
    );
    assert(
      events.every(
        (event) =>
            event.startUtc.isUtc &&
            (event.endUtc == null || event.endUtc!.isUtc),
      ),
      'Guide events must be stored in UTC',
    );
    return JetLagTimeline(
      schedule: effective,
      events: events,
      dashboard: buildDashboard(
        schedule: effective,
        events: events,
        logs: logs,
        sleepLogs: utcSleep,
        now: nowUtc,
        sleepDebtLabel: debt.label,
        sleepDebtInDebt: debt.inDebt,
      ),
      sections: buildTimelineSections(
        schedule: effective,
        logs: logs,
        now: nowUtc,
        lifestyle: lifestyle,
        settings: normalized,
        sleepLogs: utcSleep,
      ),
    );
  }
}
