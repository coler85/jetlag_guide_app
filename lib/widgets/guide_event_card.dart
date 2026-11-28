import 'package:flutter/material.dart';

import '../logic/jetlag_clock.dart';
import '../models/guide_event.dart';
import '../theme/jetlag_theme.dart';
import 'sleep_alarm_times.dart';

class GuideEventCard extends StatelessWidget {
  const GuideEventCard({
    super.key,
    required this.event,
    required this.localClock,
    required this.supportingClock,
    this.localIana,
    this.localTag,
    this.homeIana,
    this.onTap,
    this.onRegisterClockAlarm,
  });

  final GuideEvent event;
  final String localClock;
  final String supportingClock;

  /// Zones for the planned-sleep alarm. Required when [event.alarmWakeUtc] is set.
  final String? localIana;
  final String? localTag;
  final String? homeIana;
  final VoidCallback? onTap;

  /// Optional; when null the clock-alarm control stays hidden (layout tests).
  final VoidCallback? onRegisterClockAlarm;

  @override
  Widget build(BuildContext context) {
    final accent = JetlagTheme.accentFor(event.kind);
    final wake = event.alarmWakeUtc;
    final localZone = localIana;
    final tag = localTag;
    final homeZone = homeIana;
    final showAlarm =
        wake != null && localZone != null && tag != null && homeZone != null;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: JetlagTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: event.missing ? accent : JetlagTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: Icon(
                JetlagTheme.iconFor(event.kind),
                size: 16,
                color: JetlagTheme.bg,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showAlarm)
                    _SleepClockWithAlarm(
                      localClock: localClock,
                      homeClock: formatHomeSpan(
                        event.startUtc,
                        event.endUtc,
                        homeZone,
                      ),
                      wakeUtc: wake,
                      localIana: localZone,
                      localTag: tag,
                      homeIana: homeZone,
                      onRegisterClockAlarm: onRegisterClockAlarm,
                    )
                  else ...[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        localClock,
                        style: JetlagTheme.localClock,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        supportingClock,
                        style: JetlagTheme.micro.copyWith(
                          fontFeatures: JetlagTheme.tabular,
                        ),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(event.title, style: JetlagTheme.title),
                  const SizedBox(height: 2),
                  Text(event.detail, style: JetlagTheme.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: card,
      ),
    );
  }
}

class _SleepClockWithAlarm extends StatelessWidget {
  const _SleepClockWithAlarm({
    required this.localClock,
    required this.homeClock,
    required this.wakeUtc,
    required this.localIana,
    required this.localTag,
    required this.homeIana,
    this.onRegisterClockAlarm,
  });

  final String localClock;
  final String homeClock;
  final DateTime wakeUtc;
  final String localIana;
  final String localTag;
  final String homeIana;
  final VoidCallback? onRegisterClockAlarm;

  @override
  Widget build(BuildContext context) {
    final supportingStyle = JetlagTheme.micro.copyWith(
      fontFeatures: JetlagTheme.tabular,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  localClock,
                  key: const ValueKey('sleep-clock-local'),
                  style: JetlagTheme.localClock,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  homeClock,
                  key: const ValueKey('sleep-clock-supporting'),
                  style: supportingStyle,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SleepAlarmTimes(
          wakeUtc: wakeUtc,
          localIana: localIana,
          localTag: localTag,
          homeIana: homeIana,
          onRegisterClockAlarm: onRegisterClockAlarm,
        ),
      ],
    );
  }
}
