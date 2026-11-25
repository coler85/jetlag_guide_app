import 'package:flutter/material.dart';

import '../logic/guide_plan.dart';
import '../models/lifestyle.dart';
import '../theme/jetlag_theme.dart';
import 'cockpit_clock_bar.dart';
import 'lifestyle_switcher.dart';
import 'quick_log_bar.dart';
import 'status_dashboard.dart';

/// Pinned timeline header. Expanded it shows the clock, lifestyle switch,
/// sleep-debt chip, status cards, and quick log. Collapsed it keeps the
/// clock and the quick log.
class CollapsingGuideHeader extends StatelessWidget {
  const CollapsingGuideHeader({
    super.key,
    required this.clock,
    required this.localIana,
    required this.homeIana,
    required this.stationLabel,
    required this.lifestyle,
    required this.onLifestyle,
    required this.dashboard,
    required this.onCaffeine,
    required this.onMeal,
    required this.onSleep,
  });

  final DateTime Function() clock;
  final String localIana;
  final String homeIana;
  final String stationLabel;
  final JetlagLifestyle lifestyle;
  final ValueChanged<JetlagLifestyle> onLifestyle;
  final JetlagDashboard dashboard;
  final VoidCallback onCaffeine;
  final VoidCallback onMeal;
  final VoidCallback onSleep;

  static const collapsedHeight = 104.0;
  static const expandedHeight = 400.0;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _GuideHeaderDelegate(
        clock: clock,
        localIana: localIana,
        homeIana: homeIana,
        stationLabel: stationLabel,
        lifestyle: lifestyle,
        onLifestyle: onLifestyle,
        dashboard: dashboard,
        onCaffeine: onCaffeine,
        onMeal: onMeal,
        onSleep: onSleep,
      ),
    );
  }
}

class _GuideHeaderDelegate extends SliverPersistentHeaderDelegate {
  _GuideHeaderDelegate({
    required this.clock,
    required this.localIana,
    required this.homeIana,
    required this.stationLabel,
    required this.lifestyle,
    required this.onLifestyle,
    required this.dashboard,
    required this.onCaffeine,
    required this.onMeal,
    required this.onSleep,
  });

  final DateTime Function() clock;
  final String localIana;
  final String homeIana;
  final String stationLabel;
  final JetlagLifestyle lifestyle;
  final ValueChanged<JetlagLifestyle> onLifestyle;
  final JetlagDashboard dashboard;
  final VoidCallback onCaffeine;
  final VoidCallback onMeal;
  final VoidCallback onSleep;

  @override
  double get minExtent => CollapsingGuideHeader.collapsedHeight;

  @override
  double get maxExtent => CollapsingGuideHeader.expandedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final current = (maxExtent - shrinkOffset).clamp(minExtent, maxExtent);
    final opened = ((current - minExtent) / (maxExtent - minExtent)).clamp(
      0.0,
      1.0,
    );
    return SizedBox(
      key: const ValueKey('jetlag-collapsing-header'),
      height: current,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: JetlagTheme.bg,
          border: Border(
            bottom: BorderSide(
              color: opened < 0.98 ? JetlagTheme.border : Colors.transparent,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              CockpitClockBar(
                clock: clock,
                localIana: localIana,
                homeIana: homeIana,
                stationLabel: stationLabel,
              ),
              ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: opened,
                  child: Opacity(
                    opacity: opened,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        children: [
                          LifestyleSwitcher(
                            selected: lifestyle,
                            homeBaseTimezone: homeIana,
                            onChanged: onLifestyle,
                          ),
                          const SizedBox(height: 12),
                          StatusDashboard(data: dashboard),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              QuickLogBar(
                onCaffeine: onCaffeine,
                onMeal: onMeal,
                onSleep: onSleep,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_GuideHeaderDelegate oldDelegate) => true;
}
