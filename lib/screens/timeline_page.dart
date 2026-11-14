import 'package:flutter/material.dart';

import '../models/crew_log.dart';
import '../state/jetlag_guide_controller.dart';
import '../widgets/lifestyle_switcher.dart';
import '../widgets/quick_log_bar.dart';
import '../widgets/status_dashboard.dart';
import '../widgets/sticky_timeline.dart';

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key, required this.controller});

  final JetlagGuideController controller;

  @override
  Widget build(BuildContext context) {
    final timeline = controller.timeline;
    return StickyTimeline(
      sections: timeline.sections,
      schedule: timeline.schedule,
      role: controller.role,
      bunkShift: controller.bunkShift,
      onBunk: controller.selectBunk,
      onDismissLog: (id) => controller.removeLog(id),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          children: [
            LifestyleSwitcher(
              selected: controller.lifestyle,
              homeBaseTimezone: timeline.schedule.referenceTimeZone,
              onChanged: controller.setLifestyle,
            ),
            const SizedBox(height: 12),
            StatusDashboard(data: timeline.dashboard),
            const SizedBox(height: 12),
            QuickLogBar(
              sleeping: timeline.dashboard.sleeping,
              onCoffee: () => controller.addLog(CrewLogKind.coffee),
              onMeal: () => controller.addLog(CrewLogKind.meal),
              onSleep: () => controller.addLog(
                timeline.dashboard.sleeping
                    ? CrewLogKind.wake
                    : CrewLogKind.sleep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
