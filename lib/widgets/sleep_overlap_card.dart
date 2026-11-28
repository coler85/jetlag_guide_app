import 'package:flutter/material.dart';

import '../logic/sleep_overlap.dart';
import '../models/guide_event.dart';
import '../models/sleep_log.dart';
import '../theme/jetlag_theme.dart';
import 'sleep_alarm_times.dart';

/// One card for a planned sleep and the recorded sleep that overlaps it.
///
/// The plan line is not editable. Each recorded line opens that record.
class SleepOverlapCard extends StatelessWidget {
  const SleepOverlapCard({
    super.key,
    required this.plan,
    required this.logs,
    required this.iana,
    this.localTag = '',
    this.homeIana,
    this.onEditLoggedSleep,
  });

  final GuideEvent plan;
  final List<GuideEvent> logs;
  final String iana;

  /// Station tag for the planned-sleep alarm local clock.
  final String localTag;

  /// Home zone for the planned-sleep alarm supporting clock.
  final String? homeIana;
  final ValueChanged<String>? onEditLoggedSleep;

  @override
  Widget build(BuildContext context) {
    final planEnd = plan.endUtc;
    if (planEnd == null) return const SizedBox.shrink();
    final wake = plan.alarmWakeUtc;
    final homeZone = homeIana;
    final planStyle = JetlagTheme.body.copyWith(
      color: JetlagTheme.sleep,
      fontWeight: FontWeight.w700,
    );
    return DecoratedBox(
      key: const ValueKey('sleep-overlap-card'),
      decoration: BoxDecoration(
        color: JetlagTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JetlagTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      sleepPlanLine(plan.startUtc, planEnd, iana),
                      key: const ValueKey('sleep-overlap-plan'),
                      style: planStyle,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
                if (wake != null && homeZone != null && localTag.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  SleepAlarmTimes(
                    wakeUtc: wake,
                    localIana: iana,
                    localTag: localTag,
                    homeIana: homeZone,
                    localStyle: planStyle,
                  ),
                ],
              ],
            ),
            for (final log in logs) ...[
              if (log.endUtc != null) ...[
                const SizedBox(height: 6),
                _LogLine(log: log, iana: iana, onTap: _editTap(log)),
                const SizedBox(height: 4),
                Text(
                  sleepOverlapCaption(
                    planStart: plan.startUtc,
                    planEnd: planEnd,
                    logStart: log.startUtc,
                    logEnd: log.endUtc!,
                  ),
                  key: const ValueKey('sleep-overlap-caption'),
                  style: JetlagTheme.caption,
                ),
                const SizedBox(height: 8),
                _OverlapBars(
                  planStart: plan.startUtc,
                  planEnd: planEnd,
                  logStart: log.startUtc,
                  logEnd: log.endUtc!,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  VoidCallback? _editTap(GuideEvent log) {
    final onEdit = onEditLoggedSleep;
    final id = SleepLog.idFromEvent(log.id);
    if (onEdit == null || id == null) return null;
    return () => onEdit(id);
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.log, required this.iana, required this.onTap});

  final GuideEvent log;
  final String iana;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      sleepLogLine(log.startUtc, log.endUtc!, iana),
      style: JetlagTheme.body.copyWith(
        color: JetlagTheme.loggedSleep,
        fontWeight: FontWeight.w700,
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) return text;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('sleep-overlap-log'),
        onTap: onTap,
        child: text,
      ),
    );
  }
}

/// Two thin bars on one axis, from the earlier start to the later end.
class _OverlapBars extends StatelessWidget {
  const _OverlapBars({
    required this.planStart,
    required this.planEnd,
    required this.logStart,
    required this.logEnd,
  });

  final DateTime planStart;
  final DateTime planEnd;
  final DateTime logStart;
  final DateTime logEnd;

  @override
  Widget build(BuildContext context) {
    final origin = planStart.isBefore(logStart) ? planStart : logStart;
    final end = planEnd.isAfter(logEnd) ? planEnd : logEnd;
    final span = end.difference(origin).inMinutes;
    if (span <= 0) return const SizedBox.shrink();
    return Column(
      children: [
        _Bar(
          barKey: const ValueKey('sleep-overlap-plan-bar'),
          color: JetlagTheme.sleep,
          start: planStart.difference(origin).inMinutes / span,
          width: planEnd.difference(planStart).inMinutes / span,
        ),
        const SizedBox(height: 4),
        _Bar(
          barKey: const ValueKey('sleep-overlap-log-bar'),
          color: JetlagTheme.loggedSleep,
          start: logStart.difference(origin).inMinutes / span,
          width: logEnd.difference(logStart).inMinutes / span,
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.barKey,
    required this.color,
    required this.start,
    required this.width,
  });

  final Key barKey;
  final Color color;
  final double start;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final full = constraints.maxWidth;
          final left = (full * start).clamp(0.0, full);
          final bar = (full * width).clamp(0.0, full - left);
          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: JetlagTheme.elevated,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Positioned(
                left: left,
                width: bar,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  key: barKey,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
