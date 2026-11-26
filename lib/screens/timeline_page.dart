import 'dart:async';

import 'package:flutter/material.dart';

import '../models/crew_log.dart';
import '../models/sleep_log.dart';
import '../state/jetlag_guide_controller.dart';
import '../theme/jetlag_theme.dart';
import '../widgets/collapsing_guide_header.dart';
import '../widgets/sleep_log_sheet.dart';
import '../widgets/sticky_timeline.dart';

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key, required this.controller});

  final JetlagGuideController controller;

  @override
  Widget build(BuildContext context) {
    final timeline = controller.timeline;
    final schedule = timeline.schedule;
    final page = StickyTimeline(
      header: CollapsingGuideHeader(
        clock: controller.now,
        localIana: schedule.localTimeZone,
        homeIana: schedule.referenceTimeZone,
        stationLabel: schedule.stationLabel,
        lifestyle: controller.lifestyle,
        onLifestyle: controller.setLifestyle,
        dashboard: timeline.dashboard,
        onCaffeine: () => controller.addLog(CrewLogKind.caffeine),
        onMeal: () => controller.addLog(CrewLogKind.meal),
        onSleep: () => _recordSleep(context),
      ),
      sections: timeline.sections,
      schedule: timeline.schedule,
      role: controller.role,
      bunkShift: controller.bunkShift,
      onBunk: controller.selectBunk,
      onDismissLog: (id) => controller.removeLog(id),
      onEditLoggedSleep: (id) => _editSleep(context, id),
    );
    if (!controller.isSampleSchedule) return page;
    return Column(
      children: [
        const ColoredBox(
          color: JetlagTheme.elevated,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '예시 데이터입니다',
                key: ValueKey('sample-schedule-banner'),
                style: JetlagTheme.body,
              ),
            ),
          ),
        ),
        Expanded(child: page),
      ],
    );
  }

  void _recordSleep(BuildContext context) {
    unawaited(_saveSleep(context));
  }

  void _editSleep(BuildContext context, String id) {
    final existing = controller.sleepLogs
        .where((log) => log.id == id)
        .firstOrNull;
    if (existing == null) return;
    unawaited(_saveSleep(context, existing: existing));
  }

  Future<void> _saveSleep(BuildContext context, {SleepLog? existing}) async {
    final schedule = controller.timeline.schedule;
    final interval = await showSleepLogSheet(
      context: context,
      nowUtc: controller.now(),
      usualSleep: controller.settings.sleepTarget,
      iana: schedule.localTimeZone,
      zoneLabel: schedule.stationLabel,
      startUtc: existing?.startUtc,
      endUtc: existing?.endUtc,
    );
    if (interval == null) return;
    if (interval.deleted) {
      if (existing != null) await controller.removeSleepLog(existing.id);
      return;
    }
    if (existing == null) {
      await controller.addSleepLog(
        startUtc: interval.startUtc,
        endUtc: interval.endUtc,
      );
      return;
    }
    await controller.updateSleepLog(
      id: existing.id,
      startUtc: interval.startUtc,
      endUtc: interval.endUtc,
    );
  }
}
