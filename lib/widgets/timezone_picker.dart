import 'package:flutter/material.dart';

import '../logic/home_base_timezone.dart';
import '../theme/jetlag_theme.dart';

/// Home-base picker for the records tab. The value is an IANA id.
class TimezonePicker extends StatelessWidget {
  const TimezonePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final String selected;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final options = homeBaseZoneChoices(selected);
    final value = options.any((zone) => zone.id == selected)
        ? selected
        : options.first.id;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: JetlagTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JetlagTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const ValueKey('jetlag-timezone-picker'),
            isExpanded: true,
            borderRadius: BorderRadius.circular(12),
            dropdownColor: JetlagTheme.elevated,
            menuMaxHeight: 360,
            style: JetlagTheme.body,
            iconEnabledColor: JetlagTheme.textSecondary,
            iconDisabledColor: JetlagTheme.textTertiary,
            value: value,
            items: [
              for (final zone in options)
                DropdownMenuItem<String>(
                  value: zone.id,
                  child: Text(zone.menuLabel, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: enabled
                ? (next) {
                    if (next == null || next == selected) return;
                    onChanged(next);
                  }
                : null,
          ),
        ),
      ),
    );
  }
}
