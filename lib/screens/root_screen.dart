import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/jetlag_guide_controller.dart';
import '../theme/jetlag_theme.dart';
import 'records_page.dart';
import 'schedule_page.dart';
import 'timeline_page.dart';

/// Home of the standalone app: timeline, schedule, and records/settings.
///
/// [IndexedStack] keeps each tab mounted so scroll position and form state
/// survive a tab change.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<JetlagGuideController>();

    return Scaffold(
      key: const ValueKey('jetlag-guide-shell'),
      backgroundColor: JetlagTheme.bg,
      appBar: AppBar(title: const Text('시차·컨디션')),
      body: controller.isReady
          ? IndexedStack(
              index: _tab,
              children: [
                TimelinePage(controller: controller),
                SchedulePage(controller: controller),
                RecordsPage(controller: controller),
              ],
            )
          : const Center(
              key: ValueKey('jetlag-home-base-loading'),
              child: CircularProgressIndicator(),
            ),
      bottomNavigationBar: BottomNavigationBar(
        key: const ValueKey('jetlag-bottom-nav'),
        currentIndex: _tab,
        onTap: (index) => setState(() => _tab = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.timeline), label: '타임라인'),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: '스케줄',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: '기록·설정'),
        ],
      ),
    );
  }
}
