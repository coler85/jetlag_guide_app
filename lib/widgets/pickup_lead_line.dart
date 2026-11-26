import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../logic/jetlag_clock.dart';
import '../logic/layover_pickup.dart';
import '../theme/jetlag_theme.dart';

/// Date and clock on the left, lead stepper on the right, always one line.
///
/// A narrow width scales the row down instead of wrapping it.
class PickupClockLeadLine extends StatelessWidget {
  const PickupClockLeadLine({
    super.key,
    required this.clock,
    this.minutes,
    this.onLead,
    this.onClockTap,
  });

  final String clock;
  final int? minutes;
  final ValueChanged<int>? onLead;
  final VoidCallback? onClockTap;

  @override
  Widget build(BuildContext context) {
    final lead = minutes == null || onLead == null
        ? null
        : PickupLeadControls(minutes: minutes!, onChanged: onLead!);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onClockTap,
            behavior: HitTestBehavior.opaque,
            child: Text(clock, maxLines: 1, style: JetlagTheme.localClock),
          ),
          if (lead != null) ...[const SizedBox(width: 8), lead],
        ],
      ),
    );
  }
}

/// Ten-minute steps from 0 to 6 hours. The label follows [minutes].
class PickupLeadControls extends StatelessWidget {
  const PickupLeadControls({
    super.key,
    required this.minutes,
    required this.onChanged,
  });

  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('pickup-lead-controls'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(
          icon: Icons.remove_circle_outline,
          enabled: minutes > 0,
          onPressed: () => onChanged(stepPickupLead(minutes, -1)),
        ),
        const SizedBox(width: 2),
        Text(
          pickupRelativeToDeparture(minutes),
          maxLines: 1,
          style: JetlagTheme.body,
        ),
        const SizedBox(width: 2),
        _button(
          icon: Icons.add_circle_outline,
          enabled: minutes < pickupLeadMaxMinutes,
          onPressed: () => onChanged(stepPickupLead(minutes, 1)),
        ),
      ],
    );
  }

  Widget _button({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      iconSize: 20,
    );
  }
}

/// Wheel for the layover pickup. The lead stepper and the clock stay in step.
///
/// Returns the chosen instant in UTC. A null [departureUtc] hides the stepper.
Future<DateTime?> showPickupTimeSheet({
  required BuildContext context,
  required DateTime pickupUtc,
  required String iana,
  DateTime? departureUtc,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: JetlagTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _PickupTimeSheet(
      pickupUtc: pickupUtc.toUtc(),
      iana: iana,
      departureUtc: departureUtc?.toUtc(),
    ),
  );
}

class _PickupTimeSheet extends StatefulWidget {
  const _PickupTimeSheet({
    required this.pickupUtc,
    required this.iana,
    required this.departureUtc,
  });

  final DateTime pickupUtc;
  final String iana;
  final DateTime? departureUtc;

  @override
  State<_PickupTimeSheet> createState() => _PickupTimeSheetState();
}

class _PickupTimeSheetState extends State<_PickupTimeSheet> {
  late DateTime _pickup = widget.pickupUtc.toUtc();
  var _wheelEpoch = 0;

  int? get _minutes {
    final departure = widget.departureUtc;
    if (departure == null) return null;
    return pickupLeadMinutes(departure, _pickup);
  }

  @override
  Widget build(BuildContext context) {
    final wall = _wall(_pickup);
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('pickup-time-sheet'),
        height: 380,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('취소'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _pickup),
                    child: const Text('완료'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoTheme(
                data: const CupertinoThemeData(
                  brightness: Brightness.dark,
                  primaryColor: JetlagTheme.duty,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      color: JetlagTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  key: ValueKey('pickup-wheel-$_wheelEpoch'),
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  initialDateTime: DateTime(2020, 1, 1, wall.hour, wall.minute),
                  backgroundColor: JetlagTheme.card,
                  onDateTimeChanged: _onWheel,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: PickupClockLeadLine(
                clock: _stamp(wall),
                minutes: _minutes,
                onLead: widget.departureUtc == null ? null : _onLead,
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _wall(DateTime utc) {
    try {
      return wallClock(utc, widget.iana);
    } catch (_) {
      return utc.toUtc();
    }
  }

  String _stamp(DateTime wall) {
    final hour = wall.hour.toString().padLeft(2, '0');
    final minute = wall.minute.toString().padLeft(2, '0');
    return '${wall.month}월 ${wall.day}일 · $hour:$minute';
  }

  void _onWheel(DateTime value) {
    setState(() {
      _pickup = atWallTime(
        dayAnchorUtc: _pickup,
        iana: widget.iana,
        hour: value.hour,
        minute: value.minute,
      );
    });
  }

  void _onLead(int minutes) {
    final departure = widget.departureUtc;
    if (departure == null) return;
    setState(() {
      _pickup = pickupUtcFromLead(departure, minutes);
      _wheelEpoch++;
    });
  }
}
