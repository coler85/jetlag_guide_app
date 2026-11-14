import 'package:flutter/material.dart';

import '../models/crew_log.dart';
import '../theme/jetlag_theme.dart';

class QuickLogBar extends StatelessWidget {
  const QuickLogBar({
    super.key,
    required this.onCaffeine,
    required this.onMeal,
    required this.onSleep,
  });

  final VoidCallback onCaffeine;
  final VoidCallback onMeal;
  final VoidCallback onSleep;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Button(
            key: const ValueKey('log-caffeine'),
            icon: Icons.local_cafe,
            label: '카페인',
            color: JetlagTheme.caffeine,
            onPressed: onCaffeine,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Button(
            key: const ValueKey('log-meal'),
            icon: Icons.restaurant,
            label: '식사',
            color: JetlagTheme.meal,
            onPressed: onMeal,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Button(
            key: const ValueKey('log-sleep'),
            icon: Icons.bed,
            label: '수면',
            color: JetlagTheme.sleep,
            onPressed: onSleep,
          ),
        ),
      ],
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        backgroundColor: JetlagTheme.card,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: JetlagTheme.border),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

IconData iconForLog(CrewLogKind kind) {
  switch (kind) {
    case CrewLogKind.caffeine:
      return Icons.local_cafe;
    case CrewLogKind.meal:
      return Icons.restaurant;
    case CrewLogKind.sleep:
      return Icons.bed;
    case CrewLogKind.wake:
      return Icons.wb_sunny_outlined;
  }
}

Color colorForLog(CrewLogKind kind) {
  switch (kind) {
    case CrewLogKind.caffeine:
      return JetlagTheme.caffeine;
    case CrewLogKind.meal:
      return JetlagTheme.meal;
    case CrewLogKind.sleep:
      return JetlagTheme.sleep;
    case CrewLogKind.wake:
      return JetlagTheme.light;
  }
}
