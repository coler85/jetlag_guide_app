import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/jetlag_theme.dart';

/// Dark bottom sheet with a 24-hour wheel instead of the analog dial.
Future<TimeOfDay?> showWheelTimePicker({
  required BuildContext context,
  required TimeOfDay initial,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: JetlagTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _WheelTimeSheet(initial: initial),
  );
}

class _WheelTimeSheet extends StatefulWidget {
  const _WheelTimeSheet({required this.initial});

  final TimeOfDay initial;

  @override
  State<_WheelTimeSheet> createState() => _WheelTimeSheetState();
}

class _WheelTimeSheetState extends State<_WheelTimeSheet> {
  late DateTime _value = DateTime(
    2020,
    1,
    1,
    widget.initial.hour,
    widget.initial.minute,
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 300,
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
                    onPressed: () {
                      Navigator.pop(
                        context,
                        TimeOfDay(hour: _value.hour, minute: _value.minute),
                      );
                    },
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
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  initialDateTime: _value,
                  backgroundColor: JetlagTheme.card,
                  onDateTimeChanged: (value) => _value = value,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
