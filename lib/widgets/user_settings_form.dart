import 'package:flutter/material.dart';

import '../models/arrival_order.dart';
import '../models/user_settings.dart';
import '../theme/jetlag_theme.dart';
import 'sleep_log_sheet.dart';

/// Edits the personal routine. Persistence stays in the controller.
class UserSettingsForm extends StatelessWidget {
  const UserSettingsForm({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final UserSettings settings;
  final ValueChanged<UserSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('jetlag-user-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('생활 패턴', style: JetlagTheme.caption),
        const SizedBox(height: 4),
        _ClockRow(
          rowKey: const ValueKey('settings-bed'),
          label: '평소 취침',
          value: settings.defaultBedTime.label,
          onTap: () => _pickTime(
            context,
            settings.defaultBedTime,
            (time) => onChanged(settings.copyWith(defaultBedTime: time)),
          ),
        ),
        _ClockRow(
          rowKey: const ValueKey('settings-wake'),
          label: '평소 기상',
          value: settings.defaultWakeTime.label,
          onTap: () => _pickTime(
            context,
            settings.defaultWakeTime,
            (time) => onChanged(settings.copyWith(defaultWakeTime: time)),
          ),
        ),
        _DurationRow(
          rowKey: const ValueKey('settings-prep'),
          label: '외출 준비',
          minutes: settings.prepTime.inMinutes,
          onChanged: (minutes) => onChanged(
            settings.copyWith(prepTime: Duration(minutes: minutes)),
          ),
        ),
        _DurationRow(
          rowKey: const ValueKey('settings-commute'),
          label: '이동 시간',
          minutes: settings.commuteTime.inMinutes,
          maxMinutes: 240,
          onChanged: (minutes) => onChanged(
            settings.copyWith(commuteTime: Duration(minutes: minutes)),
          ),
        ),
        _DurationRow(
          rowKey: const ValueKey('settings-arrival-deboard'),
          label: '하기·입국',
          minutes: settings.arrivalDeboard.inMinutes,
          minMinutes: _arrivalPartMin(
            settings.hotelTransfer,
            settings.afterHotelReady,
          ),
          maxMinutes: _arrivalPartMax(
            settings.hotelTransfer,
            settings.afterHotelReady,
          ),
          valueLabel: _hoursMinutesLabel(settings.arrivalDeboard),
          valueWidth: 96,
          onChanged: (minutes) => onChanged(
            settings.copyWith(arrivalDeboard: Duration(minutes: minutes)),
          ),
        ),
        _DurationRow(
          rowKey: const ValueKey('settings-hotel-transfer'),
          label: '호텔 이동',
          minutes: settings.hotelTransfer.inMinutes,
          minMinutes: _arrivalPartMin(
            settings.arrivalDeboard,
            settings.afterHotelReady,
          ),
          maxMinutes: _arrivalPartMax(
            settings.arrivalDeboard,
            settings.afterHotelReady,
          ),
          valueLabel: _hoursMinutesLabel(settings.hotelTransfer),
          valueWidth: 96,
          onChanged: (minutes) => onChanged(
            settings.copyWith(hotelTransfer: Duration(minutes: minutes)),
          ),
        ),
        _DurationRow(
          rowKey: const ValueKey('settings-after-hotel'),
          label: '호텔 도착 후 준비',
          minutes: settings.afterHotelReady.inMinutes,
          minMinutes: _arrivalPartMin(
            settings.arrivalDeboard,
            settings.hotelTransfer,
          ),
          maxMinutes: _arrivalPartMax(
            settings.arrivalDeboard,
            settings.hotelTransfer,
          ),
          valueLabel: _hoursMinutesLabel(settings.afterHotelReady),
          valueWidth: 96,
          onChanged: (minutes) => onChanged(
            settings.copyWith(afterHotelReady: Duration(minutes: minutes)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '램프 도착부터 잠들기까지 합계 ${_hoursMinutesLabel(settings.arrivalToSleep)}. '
            '식사는 호텔 도착(하기+이동) 뒤에 둘 수 있어요.',
            key: const ValueKey('settings-arrival-to-sleep'),
            style: JetlagTheme.caption,
          ),
        ),
        _ArrivalOrderRow(
          selected: settings.arrivalOrder,
          onChanged: (order) =>
              onChanged(settings.copyWith(arrivalOrder: order)),
        ),
        _DurationRow(
          rowKey: const ValueKey('settings-home-showup'),
          label: '홈베이스 쇼업 (출발 ${settings.homeShowupLead.inMinutes}분 전)',
          minutes: settings.homeShowupLead.inMinutes,
          maxMinutes: 240,
          stepMinutes: 5,
          onChanged: (minutes) => onChanged(
            settings.copyWith(homeShowupLead: Duration(minutes: minutes)),
          ),
        ),
        _DurationRow(
          rowKey: const ValueKey('settings-sleep-target'),
          label: '내가 정한 수면 목표',
          minutes: settings.sleepTarget.inMinutes,
          minMinutes: UserSettings.minSleepTarget.inMinutes,
          maxMinutes: UserSettings.maxSleepTarget.inMinutes,
          stepMinutes: 30,
          valueLabel: _hoursMinutesLabel(settings.sleepTarget),
          valueWidth: 96,
          onChanged: (minutes) => onChanged(
            settings.copyWith(chosenSleep: Duration(minutes: minutes)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '하이브리드 모드 최대 이동 시간 · ${settings.hybridMaxShiftHours}시간',
          style: JetlagTheme.body,
        ),
        Slider(
          key: const ValueKey('settings-hybrid'),
          min: 1,
          max: 6,
          divisions: 5,
          label: '${settings.hybridMaxShiftHours}시간',
          value: settings.hybridMaxShiftHours.toDouble(),
          onChanged: (value) =>
              onChanged(settings.copyWith(hybridMaxShiftHours: value.round())),
        ),
      ],
    );
  }

  Future<void> _pickTime(
    BuildContext context,
    DayTime current,
    ValueChanged<DayTime> apply,
  ) async {
    final picked = await pickClockTime(
      context: context,
      initial: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    apply(DayTime(hour: picked.hour, minute: picked.minute));
  }
}

String _hoursMinutesLabel(Duration duration) {
  final minutes = duration.inMinutes;
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '$mins분';
  if (mins == 0) return '$hours시간';
  return '$hours시간 $mins분';
}

int _arrivalPartMin(Duration otherA, Duration otherB) {
  final others = otherA.inMinutes + otherB.inMinutes;
  return (UserSettings.minArrivalToSleep.inMinutes - others).clamp(
    0,
    UserSettings.maxArrivalToSleep.inMinutes,
  );
}

int _arrivalPartMax(Duration otherA, Duration otherB) {
  final others = otherA.inMinutes + otherB.inMinutes;
  return (UserSettings.maxArrivalToSleep.inMinutes - others).clamp(
    0,
    UserSettings.maxArrivalToSleep.inMinutes,
  );
}

class _ArrivalOrderRow extends StatelessWidget {
  const _ArrivalOrderRow({required this.selected, required this.onChanged});

  final ArrivalOrder selected;
  final ValueChanged<ArrivalOrder> onChanged;

  static const _keys = <ArrivalOrder, ValueKey<String>>{
    ArrivalOrder.auto: ValueKey('settings-arrival-order-auto'),
    ArrivalOrder.restFirst: ValueKey('settings-arrival-order-rest'),
    ArrivalOrder.mealFirst: ValueKey('settings-arrival-order-meal'),
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('settings-arrival-order'),
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('도착 후 순서', style: JetlagTheme.body),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final order in ArrivalOrder.values)
                ChoiceChip(
                  key: _keys[order],
                  label: Text(order.label),
                  selected: selected == order,
                  onSelected: (_) => onChanged(order),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '도착 후 식사와 수면 사이가 2시간보다 짧을 때 순서를 고릅니다.',
            style: JetlagTheme.caption,
          ),
        ],
      ),
    );
  }
}

class _ClockRow extends StatelessWidget {
  const _ClockRow({
    required this.rowKey,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final Key rowKey;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: rowKey,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: JetlagTheme.body),
      trailing: Text(value, style: JetlagTheme.localClock),
      onTap: onTap,
    );
  }
}

class _DurationRow extends StatelessWidget {
  const _DurationRow({
    required this.rowKey,
    required this.label,
    required this.minutes,
    required this.onChanged,
    this.minMinutes = 0,
    this.maxMinutes = 180,
    this.stepMinutes = 15,
    this.valueLabel,
    this.valueWidth = 64,
  });

  final Key rowKey;
  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;
  final int minMinutes;
  final int maxMinutes;
  final int stepMinutes;
  final String? valueLabel;
  final double valueWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: rowKey,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: JetlagTheme.body)),
          IconButton(
            onPressed: minutes - stepMinutes < minMinutes
                ? null
                : () => onChanged(minutes - stepMinutes),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: valueWidth,
            child: Text(
              valueLabel ?? '$minutes분',
              textAlign: TextAlign.center,
              style: JetlagTheme.body,
            ),
          ),
          IconButton(
            onPressed: minutes + stepMinutes > maxMinutes
                ? null
                : () => onChanged(minutes + stepMinutes),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}
