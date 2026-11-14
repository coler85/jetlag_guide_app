import 'package:flutter/material.dart';

import '../logic/guide_plan.dart';
import '../theme/jetlag_theme.dart';

/// Top summary: current state on the left, next pickup on the right.
class StatusDashboard extends StatelessWidget {
  const StatusDashboard({super.key, required this.data});

  final JetlagDashboard data;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _stateCard(data)),
          const SizedBox(width: 10),
          Expanded(child: _pickupCard(data)),
        ],
      ),
    );
  }

  Widget _stateCard(JetlagDashboard data) {
    final accent = data.sleeping ? JetlagTheme.sleep : JetlagTheme.duty;
    return _Panel(
      key: const ValueKey('jetlag-status-card'),
      accent: accent,
      label: '현재',
      value: data.stateLabel,
      footnote: '권장 기상',
      detail: data.wakeClock,
      detailKey: const ValueKey('jetlag-wake-clock'),
      extra: data.wakeZone,
    );
  }

  Widget _pickupCard(JetlagDashboard data) {
    return _Panel(
      key: const ValueKey('jetlag-pickup-card'),
      accent: JetlagTheme.duty,
      label: '다음 픽업',
      value: data.pickupClock,
      footnote: data.pickupZone,
      detail: data.dday,
      detailKey: const ValueKey('jetlag-dday'),
      extra: data.remaining,
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.accent,
    required this.label,
    required this.value,
    required this.footnote,
    required this.detail,
    required this.extra,
    this.detailKey,
  });

  final Color accent;
  final String label;
  final String value;
  final String footnote;
  final String detail;
  final String extra;
  final Key? detailKey;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: JetlagTheme.elevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: JetlagTheme.caption),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: JetlagTheme.clock,
            ),
            const SizedBox(height: 8),
            Text(footnote, style: JetlagTheme.caption),
            const SizedBox(height: 2),
            Text(
              detail,
              key: detailKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: JetlagTheme.body,
            ),
            const SizedBox(height: 2),
            Text(
              extra,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: JetlagTheme.caption,
            ),
          ],
        ),
      ),
    );
  }
}
