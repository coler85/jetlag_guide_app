/// Clock time on a home-base day, stored without a date or a timezone.
class DayTime {
  const DayTime({required this.hour, required this.minute});

  final int hour;
  final int minute;

  int get minuteOfDay => hour * 60 + minute;

  String get label {
    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  DayTime normalized() {
    final total = (minuteOfDay % (24 * 60) + (24 * 60)) % (24 * 60);
    return DayTime(hour: total ~/ 60, minute: total % 60);
  }

  @override
  bool operator ==(Object other) {
    return other is DayTime && other.hour == hour && other.minute == minute;
  }

  @override
  int get hashCode => Object.hash(hour, minute);
}

/// Personal routine used by the guide. Instants stay on the UTC core;
/// these fields only describe the crew's usual day.
class UserSettings {
  const UserSettings({
    this.defaultBedTime = const DayTime(hour: 23, minute: 0),
    this.defaultWakeTime = const DayTime(hour: 7, minute: 0),
    this.prepTime = const Duration(minutes: 45),
    this.commuteTime = const Duration(minutes: 60),
    this.hybridMaxShiftHours = 3,
  });

  static const defaults = UserSettings();

  /// Usual time the crew falls asleep, for example 23:00.
  final DayTime defaultBedTime;

  /// Usual time the crew wakes, for example 07:00.
  final DayTime defaultWakeTime;

  /// Time to get ready before leaving.
  final Duration prepTime;

  /// Travel time from home (or the hotel) to the report point.
  final Duration commuteTime;

  /// Largest circadian move Hybrid mode will apply, in whole hours (1–6).
  final int hybridMaxShiftHours;

  /// Length of the usual night. A wake clock that is not after bedtime
  /// belongs to the next morning.
  Duration get usualSleep {
    var minutes = defaultWakeTime.minuteOfDay - defaultBedTime.minuteOfDay;
    if (minutes <= 0) minutes += 24 * 60;
    return Duration(minutes: minutes);
  }

  UserSettings normalized() {
    return UserSettings(
      defaultBedTime: defaultBedTime.normalized(),
      defaultWakeTime: defaultWakeTime.normalized(),
      prepTime: Duration(minutes: prepTime.inMinutes.clamp(0, 180)),
      commuteTime: Duration(minutes: commuteTime.inMinutes.clamp(0, 240)),
      hybridMaxShiftHours: hybridMaxShiftHours.clamp(1, 6),
    );
  }

  UserSettings copyWith({
    DayTime? defaultBedTime,
    DayTime? defaultWakeTime,
    Duration? prepTime,
    Duration? commuteTime,
    int? hybridMaxShiftHours,
  }) {
    return UserSettings(
      defaultBedTime: defaultBedTime ?? this.defaultBedTime,
      defaultWakeTime: defaultWakeTime ?? this.defaultWakeTime,
      prepTime: prepTime ?? this.prepTime,
      commuteTime: commuteTime ?? this.commuteTime,
      hybridMaxShiftHours: hybridMaxShiftHours ?? this.hybridMaxShiftHours,
    ).normalized();
  }

  @override
  bool operator ==(Object other) {
    return other is UserSettings &&
        other.defaultBedTime == defaultBedTime &&
        other.defaultWakeTime == defaultWakeTime &&
        other.prepTime == prepTime &&
        other.commuteTime == commuteTime &&
        other.hybridMaxShiftHours == hybridMaxShiftHours;
  }

  @override
  int get hashCode => Object.hash(
    defaultBedTime,
    defaultWakeTime,
    prepTime,
    commuteTime,
    hybridMaxShiftHours,
  );
}
