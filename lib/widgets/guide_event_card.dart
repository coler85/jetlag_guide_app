import 'package:flutter/material.dart';

import '../models/guide_event.dart';
import '../theme/jetlag_theme.dart';

class GuideEventCard extends StatelessWidget {
  const GuideEventCard({
    super.key,
    required this.event,
    required this.primaryClock,
    required this.secondaryClock,
  });

  final GuideEvent event;
  final String primaryClock;
  final String secondaryClock;

  @override
  Widget build(BuildContext context) {
    final accent = JetlagTheme.accentFor(event.kind);
    return DecoratedBox(
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
                  Text(primaryClock, style: JetlagTheme.body),
                  const SizedBox(height: 2),
                  Text(event.title, style: JetlagTheme.title),
                  const SizedBox(height: 2),
                  Text(event.detail, style: JetlagTheme.caption),
                  if (secondaryClock.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(secondaryClock, style: JetlagTheme.micro),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
