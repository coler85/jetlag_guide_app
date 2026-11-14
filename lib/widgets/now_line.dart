import 'package:flutter/material.dart';

import '../theme/jetlag_theme.dart';

class NowLine extends StatelessWidget {
  const NowLine({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      key: ValueKey('jetlag-now-line'),
      height: 28,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: JetlagTheme.now,
              shape: BoxShape.circle,
            ),
            child: SizedBox(width: 8, height: 8),
          ),
          SizedBox(width: 8),
          Expanded(
            child: ColoredBox(
              color: JetlagTheme.now,
              child: SizedBox(height: 2),
            ),
          ),
          SizedBox(width: 8),
          Text(
            '지금',
            style: TextStyle(
              color: JetlagTheme.now,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
