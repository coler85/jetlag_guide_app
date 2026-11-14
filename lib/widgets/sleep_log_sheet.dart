import 'package:flutter/material.dart';

import '../logic/jetlag_clock.dart';
import '../theme/jetlag_theme.dart';

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
  final usual = usualSleep <= Duration.zero
      ? const Duration(hours: 8)
      : usualSleep;
  return showModalBottomSheet<SleepInterval>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JetlagTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return _SleepLogSheet(
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
    required this.initialStart,
    required this.initialEnd,
    required this.iana,
    required this.zoneLabel,
  });

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

  bool get _valid => _end.isAfter(_start);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final duration = _valid ? _span(_end.difference(_start)) : '시간을 확인해 주세요';
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        key: const ValueKey('sleep-log-sheet'),
        mainAxisSize: MainAxisSize.min,
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
          Text('${widget.zoneLabel} 현지 시간', style: JetlagTheme.caption),
          const SizedBox(height: 12),
          _TimeTile(
            key: const ValueKey('sleep-log-start'),
            label: '잠든 시간',
            value: _stamp(_start),
            onTap: () => _pick(start: true),
          ),
          const SizedBox(height: 8),
          _TimeTile(
            key: const ValueKey('sleep-log-end'),
            label: '기상 시간',
            value: _stamp(_end),
            onTap: () => _pick(start: false),
          ),
          const SizedBox(height: 12),
          Text(_valid ? '잔 시간 $duration' : duration, style: JetlagTheme.body),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('sleep-log-save'),
            onPressed: _valid
                ? () {
                    Navigator.of(context)
                        .pop(SleepInterval(startUtc: _start, endUtc: _end));
                  }
                : null,
            child: const Text('저장'),
          ),
        ],
      ),
    );
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

  String _stamp(DateTime utc) {
    final wall = wallClock(utc, widget.iana);
    final hm = formatHm(utc, widget.iana);
    return '${wall.month}/${wall.day} $hm';
  }

  Future<void> _pick({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await pickWallInstant(
      context: context,
      currentUtc: current,
      iana: widget.iana,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
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

Future<DateTime?> pickWallInstant({
  required BuildContext context,
  required DateTime currentUtc,
  required String iana,
}) async {
  final wall = wallClock(currentUtc, iana);
  final date = await showDatePicker(
    context: context,
    initialDate: DateTime(wall.year, wall.month, wall.day),
    firstDate: DateTime(wall.year - 1),
    lastDate: DateTime(wall.year + 2),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: wall.hour, minute: wall.minute),
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      );
    },
  );
  if (time == null) return null;
  return zonedUtc(
    iana: iana,
    year: date.year,
    month: date.month,
    day: date.day,
    hour: time.hour,
    minute: time.minute,
  );
}

Future<TimeOfDay?> pickClockTime({
  required BuildContext context,
  required TimeOfDay initial,
}) {
  return showTimePicker(
    context: context,
    initialTime: initial,
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      );
    },
  );
}
