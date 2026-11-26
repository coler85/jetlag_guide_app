import 'package:flutter/material.dart';

import '../logic/jetlag_clock.dart';
import '../logic/sleep_clock.dart';
import '../theme/jetlag_theme.dart';
import 'wheel_time_picker.dart';

/// Start and end of a sleep the crew is about to save. Both are UTC.
class SleepInterval {
  const SleepInterval({required this.startUtc, required this.endUtc});

  final DateTime startUtc;
  final DateTime endUtc;
}

Future<SleepInterval?> showSleepLogSheet({
  required BuildContext context,
  required DateTime nowUtc,
  required Duration usualSleep,
  required String iana,
  required String zoneLabel,
}) {
  final end = nowUtc.toUtc();
  final usual = usualSleep > Duration.zero ? usualSleep : Duration.zero;
  return showModalBottomSheet<SleepInterval>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JetlagTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return _SleepLogSheet(
        nowUtc: end,
        initialStart: end.subtract(usual),
        initialEnd: end,
        iana: iana,
        zoneLabel: zoneLabel,
      );
    },
  );
}

class _SleepLogSheet extends StatefulWidget {
  const _SleepLogSheet({
    required this.nowUtc,
    required this.initialStart,
    required this.initialEnd,
    required this.iana,
    required this.zoneLabel,
  });

  final DateTime nowUtc;
  final DateTime initialStart;
  final DateTime initialEnd;
  final String iana;
  final String zoneLabel;

  @override
  State<_SleepLogSheet> createState() => _SleepLogSheetState();
}

class _SleepLogSheetState extends State<_SleepLogSheet> {
  late DateTime _start = widget.initialStart.toUtc();
  late DateTime _end = widget.initialEnd.toUtc();

  /// Calendar day the crew picked. Null keeps the bed clock on its latest occurrence.
  DateTime? _pinnedDay;

  bool get _valid => _end.isAfter(_start);

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final duration = _valid ? _span(_end.difference(_start)) : '시간을 확인해 주세요';
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        child: Column(
          key: const ValueKey('sleep-log-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: JetlagTheme.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('수면 기록', style: JetlagTheme.title),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.zoneLabel} 현지 시간',
                      style: JetlagTheme.caption,
                    ),
                    const SizedBox(height: 12),
                    _TimeTile(
                      key: const ValueKey('sleep-log-start'),
                      label: '잠든 시간',
                      value: formatHm(_start, widget.iana),
                      onTap: () => _pick(start: true),
                    ),
                    const SizedBox(height: 8),
                    _TimeTile(
                      key: const ValueKey('sleep-log-end'),
                      label: '기상 시간',
                      value: formatHm(_end, widget.iana),
                      onTap: () => _pick(start: false),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _whenLabel(),
                      key: const ValueKey('sleep-log-when'),
                      style: JetlagTheme.body,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const ValueKey('sleep-log-date'),
                        onPressed: _pickDate,
                        child: const Text('날짜 바꾸기'),
                      ),
                    ),
                    Text(
                      _valid ? '잔 시간 $duration' : duration,
                      style: JetlagTheme.body,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: FilledButton(
                key: const ValueKey('sleep-log-save'),
                onPressed: _valid
                    ? () {
                        Navigator.of(context)
                            .pop(SleepInterval(startUtc: _start, endUtc: _end));
                      }
                    : null,
                child: const Text('저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _whenLabel() {
    final bed = wallClock(_start, widget.iana);
    final wake = wallClock(_end, widget.iana);
    final bedText =
        '${bed.month}월 ${bed.day}일 ${formatHm(_start, widget.iana)}';
    final sameDay =
        bed.year == wake.year && bed.month == wake.month && bed.day == wake.day;
    final wakeText = sameDay
        ? formatHm(_end, widget.iana)
        : '${wake.month}월 ${wake.day}일 ${formatHm(_end, widget.iana)}';
    return '$bedText - $wakeText';
  }

  String _span(Duration duration) {
    final minutes = duration.inMinutes;
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    final parts = <String>[
      if (hours > 0) '$hours시간',
      if (mins > 0 || hours == 0) '$mins분',
    ];
    return parts.join(' ');
  }

  Future<void> _pick({required bool start}) async {
    final current = start ? _start : _end;
    final wall = wallClock(current, widget.iana);
    final time = await showWheelTimePicker(
      context: context,
      initial: TimeOfDay(hour: wall.hour, minute: wall.minute),
    );
    if (time == null || !mounted) return;
    setState(() {
      if (start) {
        _place(bedHour: time.hour, bedMinute: time.minute);
      } else {
        _place(wakeHour: time.hour, wakeMinute: time.minute);
      }
    });
  }

  Future<void> _pickDate() async {
    final wall = wallClock(_start, widget.iana);
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(wall.year, wall.month, wall.day),
      firstDate: DateTime(wall.year - 1),
      lastDate: DateTime(wall.year + 2),
    );
    if (date == null || !mounted) return;
    setState(() {
      _pinnedDay = DateTime.utc(date.year, date.month, date.day);
      _place();
    });
  }

  void _place({int? bedHour, int? bedMinute, int? wakeHour, int? wakeMinute}) {
    final bed = wallClock(_start, widget.iana);
    final wake = wallClock(_end, widget.iana);
    final resolved = resolveSleepInterval(
      nowUtc: widget.nowUtc,
      iana: widget.iana,
      bedHour: bedHour ?? bed.hour,
      bedMinute: bedMinute ?? bed.minute,
      wakeHour: wakeHour ?? wake.hour,
      wakeMinute: wakeMinute ?? wake.minute,
      pinnedDay: _pinnedDay,
    );
    _start = resolved.startUtc;
    _end = resolved.endUtc;
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: JetlagTheme.elevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(child: Text(label, style: JetlagTheme.body)),
              Text(value, style: JetlagTheme.localClock),
            ],
          ),
        ),
      ),
    );
  }
}

Future<TimeOfDay?> pickClockTime({
  required BuildContext context,
  required TimeOfDay initial,
}) {
  return showWheelTimePicker(context: context, initial: initial);
}
