import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/flight_schedule_input.dart';
import '../sample_schedule.dart';
import '../state/jetlag_guide_controller.dart';
import '../theme/jetlag_theme.dart';
import 'records_page.dart';
import 'schedule_page.dart';
import 'timeline_page.dart';

/// Home of the standalone app: timeline, schedule, and records/settings.
///
/// [schedule] is the optional layover from a roster app or a deep link.
/// [IndexedStack] keeps each tab mounted so scroll position and form state
/// survive a tab change.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key, this.schedule});

  final FlightScheduleInput? schedule;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _tab = 0;
  var _handedOff = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final input = widget.schedule;
    if (_handedOff || input == null) return;
    _handedOff = true;
    final controller = context.read<JetlagGuideController>();
    if (!controller.hasSchedule) controller.adoptSchedule(input);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<JetlagGuideController>();
    final ready = controller.isReady;
    final hasSchedule = controller.hasSchedule;

    return Scaffold(
      key: const ValueKey('jetlag-guide-shell'),
      backgroundColor: JetlagTheme.bg,
      appBar: AppBar(title: const Text('시차·컨디션')),
      body: ready
          ? IndexedStack(
              index: _tab,
              children: [
                hasSchedule
                    ? TimelinePage(controller: controller)
                    : const _ScheduleMissing(
                        key: ValueKey('jetlag-empty-schedule'),
                      ),
                hasSchedule
                    ? SchedulePage(controller: controller)
                    : const _ScheduleMissing(),
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

class _ScheduleMissing extends StatelessWidget {
  const _ScheduleMissing({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('일정이 없습니다', style: JetlagTheme.title),
            const SizedBox(height: 8),
            const Text(
              '로스터 앱이나 딥링크로 비행 일정이 들어오면 시차 가이드가 만들어집니다.',
              style: JetlagTheme.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                context.read<JetlagGuideController>().adoptSchedule(
                  sampleFlightSchedule(),
                );
              },
              child: const Text('샘플 일정 보기'),
            ),
          ],
        ),
      ),
    );
  }
}
