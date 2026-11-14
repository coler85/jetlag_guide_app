import 'package:flutter/material.dart';

import '../logic/guide_plan.dart';
import '../logic/jetlag_clock.dart';
import '../models/bunk_shift.dart';
import '../models/jetlag_schedule.dart';
import '../theme/jetlag_theme.dart';
import 'bunk_selection_card.dart';
import 'guide_event_card.dart';
import 'inline_log_chip.dart';
import 'now_line.dart';

class StickyTimeline extends StatelessWidget {
  const StickyTimeline({
    super.key,
    required this.header,
    required this.sections,
    required this.schedule,
    required this.role,
    required this.bunkShift,
    required this.onBunk,
    required this.onDismissLog,
  });

  final Widget header;
  final List<TimelineSection> sections;
  final JetlagScheduleSnapshot schedule;
  final JetlagCrewRole role;
  final BunkShift? bunkShift;
  final ValueChanged<BunkShift> onBunk;
  final ValueChanged<String> onDismissLog;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const ValueKey('jetlag-timeline'),
      primary: false,
      slivers: [
        SliverToBoxAdapter(child: header),
        for (final section in sections) ...[
          SliverPersistentHeader(
            pinned: true,
            delegate: _DateHeaderDelegate(section.heading),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _row(section.markers[index]),
                );
              }, childCount: section.markers.length),
            ),
          ),
        ],
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 28),
            child: Text(JetlagTheme.disclaimer, style: JetlagTheme.micro),
          ),
        ),
      ],
    );
  }

  Widget _row(TimelineMarker marker) {
    final child = switch (marker) {
      EventMarker event => GuideEventCard(
        event: event.event,
        primaryClock: formatRange(
          event.event.startUtc,
          event.event.endUtc,
          schedule.localTimeZone,
        ),
        secondaryClock: _secondary(event),
      ),
      LogMarker log => InlineLogChip(
        log: log.log,
        clock: formatHm(log.log.atUtc, schedule.localTimeZone),
        onDismiss: () => onDismissLog(log.log.id),
      ),
      NowMarker() => const NowLine(),
      BunkMarker() => BunkSelectionCard(
        schedule: schedule,
        role: role,
        selected: bunkShift,
        onSelected: onBunk,
      ),
    };
    final dimmed = switch (marker) {
      EventMarker event => event.dimmed,
      LogMarker log => log.dimmed,
      _ => false,
    };
    if (!dimmed) return child;
    return Opacity(opacity: JetlagTheme.pastOpacity, child: child);
  }

  String _secondary(EventMarker marker) {
    if (schedule.localTimeZone == schedule.referenceTimeZone) return '';
    final clock = formatRange(
      marker.event.startUtc,
      marker.event.endUtc,
      schedule.referenceTimeZone,
    );
    final zone = zoneAbbreviation(
      marker.event.startUtc,
      schedule.referenceTimeZone,
    );
    return '$clock $zone';
  }
}

class _DateHeaderDelegate extends SliverPersistentHeaderDelegate {
  _DateHeaderDelegate(this.heading);

  final String heading;

  @override
  double get minExtent => 40;

  @override
  double get maxExtent => 40;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: JetlagTheme.bg,
        border: Border(
          bottom: BorderSide(
            color: overlapsContent ? JetlagTheme.border : Colors.transparent,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(heading, style: JetlagTheme.caption),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_DateHeaderDelegate oldDelegate) {
    return oldDelegate.heading != heading;
  }
}
