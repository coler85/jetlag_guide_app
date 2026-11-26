import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/flight_schedule_input.dart';
import '../sample_schedule.dart';
import '../services/ke_roster_gateway.dart';
import '../state/jetlag_guide_controller.dart';
import '../theme/jetlag_theme.dart';
import '../widgets/manual_schedule_form.dart';
import 'records_page.dart';
import 'schedule_screen.dart';
import 'timeline_page.dart';

/// Home of the standalone app: timeline, schedule, and records/settings.
///
/// [schedule] is the optional layover from a roster app or a deep link.
/// When it is present at launch, the timeline is the first tab and the intake
/// screen is skipped. [IndexedStack] keeps each tab mounted.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key, this.schedule});

  final FlightScheduleInput? schedule;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  late final KeRosterGateway _roster;
  late final StreamSubscription<FlightScheduleInput> _rosterSub;
  JetlagGuideController? _listened;
  int _tab = 0;
  var _handedOff = false;
  var _tabReady = false;
  var _tabChosen = false;

  @override
  void initState() {
    super.initState();
    _roster = KeRosterGateway();
    _roster.bind();
    _rosterSub = _roster.incoming.listen(_onIncomingSchedule);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumeColdLink());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<JetlagGuideController>();
    if (!identical(_listened, controller)) {
      _listened?.removeListener(_placeTab);
      _listened = controller;
      controller.addListener(_placeTab);
    }
    final injected = widget.schedule;
    if (!_handedOff && injected != null) {
      _handedOff = true;
      if (!controller.hasSchedule) {
        unawaited(controller.adoptSchedule(injected));
      }
    }
    _placeTab();
  }

  @override
  void dispose() {
    _listened?.removeListener(_placeTab);
    _rosterSub.cancel();
    _roster.dispose();
    super.dispose();
  }

  /// Opens the timeline once a saved layover is restored, otherwise the guide.
  void _placeTab() {
    if (_tabReady || !mounted) return;
    final controller = _listened;
    if (controller == null || !controller.isReady) return;
    _tabReady = true;
    if (_tabChosen) return;
    final next = controller.hasSchedule ? 0 : 1;
    if (_tab == next) return;
    setState(() => _tab = next);
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
                    : _ScheduleMissing(
                        key: const ValueKey('jetlag-empty-schedule'),
                        onOpenSchedule: () => setState(() => _tab = 1),
                      ),
                ScheduleScreen(
                  controller: controller,
                  roster: _roster,
                  onSchedule: _onIncomingSchedule,
                ),
                RecordsPage(
                  controller: controller,
                  onScheduleCleared: () {
                    if (!mounted) return;
                    setState(() => _tab = 1);
                  },
                ),
              ],
            )
          : const Center(
              key: ValueKey('jetlag-home-base-loading'),
              child: CircularProgressIndicator(),
            ),
      bottomNavigationBar: BottomNavigationBar(
        key: const ValueKey('jetlag-bottom-nav'),
        currentIndex: _tab,
        onTap: (index) {
          _tabChosen = true;
          setState(() => _tab = index);
        },
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

  Future<void> _consumeColdLink() async {
    try {
      final input = await _roster.takeInitialLink();
      if (!mounted || input == null || widget.schedule != null) return;
      _onIncomingSchedule(input);
    } catch (error, stack) {
      debugPrint('schedule launch link failed: $error\n$stack');
    }
  }

  void _onIncomingSchedule(FlightScheduleInput input) {
    if (!mounted) return;
    unawaited(context.read<JetlagGuideController>().adoptSchedule(input));
    setState(() => _tab = 0);
    Navigator.of(context).popUntil((route) {
      final name = route.settings.name;
      return name != KeRosterGateway.waitRouteName &&
          name != ManualScheduleForm.routeName &&
          name != ScheduleScreen.parseRouteName;
    });
  }
}

class _ScheduleMissing extends StatelessWidget {
  const _ScheduleMissing({super.key, required this.onOpenSchedule});

  final VoidCallback onOpenSchedule;

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
              '스케줄 탭에서 파일 또는 직접 입력으로 비행 일정을 넣을 수 있습니다.',
              style: JetlagTheme.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onOpenSchedule,
              child: const Text('스케줄 가져오기'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                unawaited(
                  context.read<JetlagGuideController>().adoptSchedule(
                    sampleFlightSchedule(),
                    sample: true,
                  ),
                );
              },
              child: const Text('예시 일정 둘러보기'),
            ),
          ],
        ),
      ),
    );
  }
}
