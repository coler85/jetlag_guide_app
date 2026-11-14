import 'package:flutter/material.dart';

import '../models/lifestyle.dart';
import '../theme/jetlag_theme.dart';

/// Home-base / hybrid / local switch, placed above the summary cards.
class LifestyleSwitcher extends StatelessWidget {
  const LifestyleSwitcher({
    super.key,
    required this.selected,
    required this.homeBaseTimezone,
    required this.onChanged,
  });

  final JetlagLifestyle selected;
  final String homeBaseTimezone;
  final ValueChanged<JetlagLifestyle> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<JetlagLifestyle>(
      key: const ValueKey('jetlag-lifestyle'),
      showSelectedIcon: false,
      segments: [
        for (final lifestyle in JetlagLifestyle.values)
          ButtonSegment<JetlagLifestyle>(
            value: lifestyle,
            label: Text(
              lifestyle.switchLabel(homeBaseTimezone),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
      ],
      selected: {selected},
      onSelectionChanged: (next) {
        if (next.isEmpty) return;
        onChanged(next.first);
      },
      style: SegmentedButton.styleFrom(
        foregroundColor: JetlagTheme.textPrimary,
        selectedForegroundColor: JetlagTheme.bg,
        selectedBackgroundColor: JetlagTheme.duty,
        side: const BorderSide(color: JetlagTheme.border),
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
