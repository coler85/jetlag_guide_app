import 'package:flutter/material.dart';

import '../logic/jetlag_clock.dart';
import '../theme/jetlag_theme.dart';

/// Alarm wake on the right of a planned-sleep clock row.
///
/// Primary line matches [localStyle] (same weight as the sleep span).
/// Home wake sits under it, on the same row as the card home span (no UTC).
class SleepAlarmTimes extends StatelessWidget {
  const SleepAlarmTimes({
    super.key,
    required this.wakeUtc,
    required this.localIana,
    required this.localTag,
    required this.homeIana,
    this.localStyle = JetlagTheme.localClock,
  });

  final DateTime wakeUtc;
  final String localIana;
  final String localTag;
  final String homeIana;
  final TextStyle localStyle;

  @override
  Widget build(BuildContext context) {
    final local = formatAlarmLocal(wakeUtc, localIana, localTag);
    final home = formatAlarmHome(wakeUtc, homeIana);
    return Column(
      key: const ValueKey('sleep-alarm'),
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.alarm,
              size: (localStyle.fontSize ?? 17) - 1,
              color: localStyle.color ?? JetlagTheme.textPrimary,
            ),
            const SizedBox(width: 4),
            Text(
              local,
              key: const ValueKey('sleep-alarm-local'),
              style: localStyle,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.end,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          home,
          key: const ValueKey('sleep-alarm-home'),
          style: JetlagTheme.micro.copyWith(fontFeatures: JetlagTheme.tabular),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          textAlign: TextAlign.end,
        ),
      ],
    );
  }
}
