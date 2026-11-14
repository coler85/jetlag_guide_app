import 'package:flutter/material.dart';

import 'models/jetlag_schedule.dart';
import 'notifications/jetlag_alert_scheduler.dart';
import 'sample_schedule.dart';
import 'screens/jetlag_guide_shell.dart';
import 'state/jetlag_log_store.dart';

/// Opens the guide as a full-screen dialog on the root navigator, so the
/// roster tab bar stays underneath the route.
Future<void> openJetlagGuide(
  BuildContext context, {
  JetlagScheduleSnapshot? schedule,
  DateTime Function()? now,
  JetlagLogStore? logStore,
  JetlagAlertScheduler? alerts,
}) {
  final snapshot = schedule ?? sampleJetlagSchedule(now: now?.call());
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => JetlagGuideShell(
        schedule: snapshot,
        now: now,
        logStore: logStore ?? const JetlagLogStore(),
        alerts: alerts,
      ),
    ),
  );
}
