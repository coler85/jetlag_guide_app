import 'package:flutter/material.dart';

import '../models/crew_log.dart';
import '../theme/jetlag_theme.dart';
import 'quick_log_bar.dart';

/// One thin row for a crew log, with a cancel control on the right.
class InlineLogChip extends StatelessWidget {
  const InlineLogChip({
    super.key,
    required this.log,
    required this.clock,
    required this.onDismiss,
  });

  final CrewLog log;
  final String clock;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = colorForLog(log.kind);
    return Material(
      color: JetlagTheme.elevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: color.withValues(alpha: 0.45)),
      ),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            const SizedBox(width: 10),
            Icon(iconForLog(log.kind), size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${log.kind.label}  $clock',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JetlagTheme.body,
              ),
            ),
            IconButton(
              key: ValueKey('log-chip-dismiss-${log.id}'),
              tooltip: '취소',
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 16),
              color: JetlagTheme.textSecondary,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            ),
          ],
        ),
      ),
    );
  }
}
