import 'package:flutter/material.dart';

import '../logic/jetlag_clock.dart';
import '../state/jetlag_guide_controller.dart';
import '../theme/jetlag_theme.dart';

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key, required this.controller});

  final JetlagGuideController controller;

  @override
  Widget build(BuildContext context) {
    final schedule = controller.schedule;
    final pickup = schedule.pickupUtc;
    return ListView(
      key: const ValueKey('jetlag-schedule-page'),
      primary: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const Text('STA·STD·스테이션은 이 화면 밖에서 주입됩니다.', style: JetlagTheme.caption),
        const SizedBox(height: 12),
        _Fact(label: '스테이션', value: schedule.stationLabel),
        _Fact(label: '시간대', value: schedule.localTimeZone),
        _Fact(label: '도착 STA', value: _clocks(schedule.staUtc)),
        _Fact(label: '출발 STD', value: _clocks(schedule.stdUtc)),
        _Fact(
          label: '편명',
          value: schedule.flightNumber.isEmpty ? '—' : schedule.flightNumber,
        ),
        _Fact(label: '픽업', value: pickup == null ? '미입력' : _clocks(pickup)),
        if (schedule.showupUtc != null)
          _Fact(label: '쇼업', value: _clocks(schedule.showupUtc!)),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _editPickup(context),
          child: const Text('픽업 시간 수정'),
        ),
      ],
    );
  }

  String _clocks(DateTime utc) {
    final schedule = controller.schedule;
    final local = formatHm(utc, schedule.localTimeZone);
    final homeZone = zoneAbbreviation(utc, schedule.referenceTimeZone);
    if (schedule.localTimeZone == schedule.referenceTimeZone) {
      return '$local $homeZone';
    }
    final home = formatHm(utc, schedule.referenceTimeZone);
    return '$local ${schedule.stationLabel} · $home $homeZone';
  }

  Future<void> _editPickup(BuildContext context) async {
    final schedule = controller.schedule;
    final anchor = (schedule.pickupUtc ?? schedule.stdUtc).toUtc();
    final wall = wallClock(anchor, schedule.localTimeZone);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: wall.hour, minute: wall.minute),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null) return;
    final next = atWallTime(
      dayAnchorUtc: anchor,
      iana: schedule.localTimeZone,
      hour: picked.hour,
      minute: picked.minute,
    );
    await controller.setPickup(next);
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: JetlagTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: JetlagTheme.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: JetlagTheme.caption),
              const SizedBox(height: 2),
              Text(value, style: JetlagTheme.body),
            ],
          ),
        ),
      ),
    );
  }
}
