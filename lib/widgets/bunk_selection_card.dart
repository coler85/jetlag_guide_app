import 'package:flutter/material.dart';

import '../logic/bunk_plan.dart';
import '../models/bunk_shift.dart';
import '../models/jetlag_schedule.dart';
import '../theme/jetlag_theme.dart';

/// Shift picker. Choosing a slot expands that slot's rest timeline.
class BunkSelectionCard extends StatefulWidget {
  const BunkSelectionCard({
    super.key,
    required this.schedule,
    required this.role,
    required this.selected,
    required this.onSelected,
  });

  final JetlagScheduleSnapshot schedule;
  final JetlagCrewRole role;
  final BunkShift? selected;
  final ValueChanged<BunkShift> onSelected;

  @override
  State<BunkSelectionCard> createState() => _BunkSelectionCardState();
}

class _BunkSelectionCardState extends State<BunkSelectionCard> {
  final ExpansibleController _tile = ExpansibleController();

  @override
  void didUpdateWidget(BunkSelectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected == null && oldWidget.selected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setOpen(false));
    } else if (widget.selected != null &&
        widget.selected != oldWidget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setOpen(true));
    }
  }

  void _setOpen(bool open) {
    if (!mounted) return;
    if (open && !_tile.isExpanded) _tile.expand();
    if (!open && _tile.isExpanded) _tile.collapse();
  }

  @override
  Widget build(BuildContext context) {
    final shifts = BunkShift.forRole(widget.role);
    final selected = widget.selected;
    final cues = selected == null
        ? const <BunkCue>[]
        : buildBunkPlan(widget.schedule, selected);
    return Material(
      key: const ValueKey('jetlag-bunk-card'),
      color: JetlagTheme.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: JetlagTheme.duty.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('기내 벙크', style: JetlagTheme.title),
            const SizedBox(height: 2),
            Text(
              widget.role == JetlagCrewRole.flightOps
                  ? '운항 · P1 후반휴식 / P2 전반휴식'
                  : '객실 · 1교대 / 2교대',
              style: JetlagTheme.caption,
            ),
            const SizedBox(height: 10),
            SegmentedButton<BunkShift>(
              showSelectedIcon: false,
              emptySelectionAllowed: true,
              segments: [
                for (final shift in shifts)
                  ButtonSegment<BunkShift>(
                    value: shift,
                    label: Text(shift.label),
                  ),
              ],
              selected: selected == null ? const <BunkShift>{} : {selected},
              onSelectionChanged: (next) {
                if (next.isEmpty) return;
                widget.onSelected(next.first);
              },
              style: SegmentedButton.styleFrom(
                foregroundColor: JetlagTheme.textPrimary,
                selectedForegroundColor: JetlagTheme.bg,
                selectedBackgroundColor: JetlagTheme.duty,
                side: const BorderSide(color: JetlagTheme.border),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ExpansionTile(
              controller: _tile,
              initiallyExpanded: false,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              iconColor: JetlagTheme.textSecondary,
              collapsedIconColor: JetlagTheme.textSecondary,
              title: Text(
                selected == null ? '맞춤 타임라인' : '${selected.label} 기내 휴식',
                style: JetlagTheme.body,
              ),
              subtitle: const Text(
                '조를 고르면 아래로 펼쳐집니다',
                style: JetlagTheme.caption,
              ),
              children: [for (final cue in cues) _CueRow(cue: cue)],
            ),
          ],
        ),
      ),
    );
  }
}

class _CueRow extends StatelessWidget {
  const _CueRow({required this.cue});

  final BunkCue cue;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (cue.kind) {
      BunkCueKind.caffeine => (Icons.local_cafe, JetlagTheme.caffeine),
      BunkCueKind.sleep => (Icons.bed, JetlagTheme.sleep),
      BunkCueKind.wake => (Icons.wb_sunny_outlined, JetlagTheme.light),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cue.title, style: JetlagTheme.caption),
                Text(cue.window, style: JetlagTheme.localClock),
                Text(
                  cue.supporting,
                  style: JetlagTheme.micro.copyWith(
                    fontFeatures: JetlagTheme.tabular,
                  ),
                ),
                Text(cue.detail, style: JetlagTheme.micro),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
