import 'dart:async';

import 'package:flutter/material.dart';

import '../models/crew_log.dart';
import '../state/jetlag_guide_controller.dart';
import '../theme/jetlag_theme.dart';
import '../widgets/cockpit_clock_bar.dart';
import '../widgets/lifestyle_switcher.dart';
import '../widgets/quick_log_bar.dart';
import '../widgets/sleep_log_sheet.dart';
import '../widgets/status_dashboard.dart';
import '../widgets/sticky_timeline.dart';

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key, required this.controller});

  final JetlagGuideController controller;

  @override
  Widget build(BuildContext context) {
    final timeline = controller.timeline;
    final schedule = timeline.schedule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            color: JetlagTheme.bg,
            border: Border(bottom: BorderSide(color: JetlagTheme.border)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CockpitClockBar(
                  clock: controller.now,
                  localIana: schedule.localTimeZone,
                  homeIana: schedule.referenceTimeZone,
                  stationLabel: schedule.stationLabel,
                ),
                const SizedBox(height: 12),
                LifestyleSwitcher(
                  selected: controller.lifestyle,
                  homeBaseTimezone: schedule.referenceTimeZone,
                  onChanged: controller.setLifestyle,
                ),
                const SizedBox(height: 12),
                StatusDashboard(data: timeline.dashboard),
                const SizedBox(height: 12),
                QuickLogBar(
                  onCaffeine: () => controller.addLog(CrewLogKind.caffeine),
                  onMeal: () => controller.addLog(CrewLogKind.meal),
                  onSleep: () => _recordSleep(context),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: StickyTimeline(
            sections: timeline.sections,
            schedule: timeline.schedule,
            role: controller.role,
            bunkShift: controller.bunkShift,
            onBunk: controller.selectBunk,
            onDismissLog: (id) => controller.removeLog(id),
          ),
        ),
      ],
    );
  }

  void _recordSleep(BuildContext context) {
    final schedule = controller.timeline.schedule;
    unawaited(() async {
      final interval = await showSleepLogSheet(
        context: context,
        nowUtc: controller.now(),
        usualSleep: controller.settings.usualSleep,
        iana: schedule.localTimeZone,
        zoneLabel: schedule.stationLabel,
      );
      if (interval == null) return;
      await controller.addSleepLog(
        startUtc: interval.startUtc,
        endUtc: interval.endUtc,
      );
    }());
  }
}
