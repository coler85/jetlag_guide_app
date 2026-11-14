import 'package:flutter/foundation.dart';

import '../models/crew_log.dart';
import '../models/guide_event.dart';
import '../models/jetlag_schedule.dart';
import '../models/lifestyle.dart';
import 'guide_plan.dart';
import 'home_base_timezone.dart';

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
        wakeClock: '—',
        wakeZone: '시간대를 계산하지 못했습니다',
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

  JetLagTimeline calculate({
    required JetlagScheduleSnapshot schedule,
    required JetlagLifestyle lifestyle,
    required List<CrewLog> logs,
    required DateTime now,
    required String homeBaseTimezone,
  }) {
    try {
      return _build(
        schedule: schedule,
        lifestyle: lifestyle,
        logs: logs,
        now: now,
        homeBaseTimezone: homeBaseTimezone,
      );
    } catch (error, stack) {
      debugPrint('JetLagCalculator fallback: $error\n$stack');
      try {
        return _build(
          schedule: schedule,
          lifestyle: lifestyle,
          logs: logs,
          now: now,
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
    required DateTime now,
    required String homeBaseTimezone,
  }) {
    final home = resolveHomeBaseTimezone(homeBaseTimezone);
    final effective = schedule.copyWith(referenceTimeZone: home);
    final events = buildGuideEvents(effective, lifestyle: lifestyle);
    return JetLagTimeline(
      schedule: effective,
      events: events,
      dashboard: buildDashboard(
        schedule: effective,
        events: events,
        logs: logs,
        now: now,
      ),
      sections: buildTimelineSections(
        schedule: effective,
        logs: logs,
        now: now,
        lifestyle: lifestyle,
      ),
    );
  }
}
