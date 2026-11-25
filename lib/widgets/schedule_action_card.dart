import 'package:flutter/material.dart';

import '../theme/jetlag_theme.dart';

/// Large intake action. The emoji is the scan target; the accent is the edge.
class ScheduleActionCard extends StatelessWidget {
  const ScheduleActionCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: JetlagTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: JetlagTheme.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.9),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(17),
                    ),
                  ),
                  child: const SizedBox(width: 5),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
                    child: Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: Center(
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 26),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: JetlagTheme.body),
                              const SizedBox(height: 4),
                              Text(subtitle, style: JetlagTheme.caption),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: JetlagTheme.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
