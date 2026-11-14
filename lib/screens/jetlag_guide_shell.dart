import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/jetlag_clock.dart';
import '../models/jetlag_schedule.dart';
import '../notifications/jetlag_alert_scheduler.dart';
import '../state/jetlag_guide_controller.dart';
import '../state/jetlag_log_store.dart';
import '../state/jetlag_state.dart';
import '../theme/jetlag_theme.dart';
import 'root_screen.dart';

/// Full-screen guide. Hosts [RootScreen] so a roster modal and the standalone
/// app share one tab bar.
class JetlagGuideShell extends StatefulWidget {
  const JetlagGuideShell({
    super.key,
    required this.schedule,
    this.now,
    this.logStore = const JetlagLogStore(),
    this.alerts,
    this.homeBase,
  });

  final JetlagScheduleSnapshot schedule;
  final DateTime Function()? now;
  final JetlagLogStore logStore;
  final JetlagAlertScheduler? alerts;

  /// Injected home-base state. The shell owns it and disposes it with the
  /// controller. Tests use this to hold loading open until preferences arrive.
  final JetLagState? homeBase;

  @override
  State<JetlagGuideShell> createState() => _JetlagGuideShellState();
}

class _JetlagGuideShellState extends State<JetlagGuideShell> {
  late final JetlagGuideController _controller;

  @override
  void initState() {
    super.initState();
    ensureJetlagTimeZones();
    _controller = JetlagGuideController(
      schedule: widget.schedule,
      now: widget.now,
      logStore: widget.logStore,
      alerts: widget.alerts ?? JetlagLocalAlertScheduler(),
      homeBase: widget.homeBase,
    );
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: JetlagTheme.material,
      child: ChangeNotifierProvider<JetlagGuideController>.value(
        value: _controller,
        child: const RootScreen(),
      ),
    );
  }
}
