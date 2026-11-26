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
    this.homeShowupLead = const Duration(minutes: 95),
    this.chosenSleep = const Duration(hours: 7),
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

  /// How long before the outbound STD the crew shows up at home base,
  /// when a journey does not name its own show-up. Clamped to 0–240 minutes.
  final Duration homeShowupLead;

  /// Stored length behind [sleepTarget]. Clamped to 4–9 hours on 30-minute steps.
  final Duration chosenSleep;

  static const minSleepTarget = Duration(hours: 4);
  static const maxSleepTarget = Duration(hours: 9);

  /// Leave home this long before [showupUtc].
  DateTime departHomeUtc(DateTime showupUtc) {
    return showupUtc.toUtc().subtract(normalized().commuteTime);
  }

  /// Wake this long before [departHomeUtc].
  DateTime wakeForShowupUtc(DateTime showupUtc) {
    return departHomeUtc(showupUtc).subtract(normalized().prepTime);
  }

  /// Length of the usual night. A wake clock that is not after bedtime
  /// belongs to the next morning.
  Duration get usualSleep {
    var minutes = defaultWakeTime.minuteOfDay - defaultBedTime.minuteOfDay;
    if (minutes <= 0) minutes += 24 * 60;
    return Duration(minutes: minutes);
  }

  /// Hours each saved sleep is compared with, and the planned block before
  /// a pickup. This is the only sleep goal the guide reads.
  Duration get sleepTarget => clampSleepTarget(chosenSleep);

  /// Keeps a sleep goal inside 4–9 hours, on a 30-minute step.
  static Duration clampSleepTarget(Duration value) {
    final minutes = value.inMinutes.clamp(
      minSleepTarget.inMinutes,
      maxSleepTarget.inMinutes,
    );
    final snapped = ((minutes / 30).round() * 30).clamp(
      minSleepTarget.inMinutes,
      maxSleepTarget.inMinutes,
    );
    return Duration(minutes: snapped.toInt());
  }

  UserSettings normalized() {
    return UserSettings(
      defaultBedTime: defaultBedTime.normalized(),
      defaultWakeTime: defaultWakeTime.normalized(),
      prepTime: Duration(minutes: prepTime.inMinutes.clamp(0, 180)),
      commuteTime: Duration(minutes: commuteTime.inMinutes.clamp(0, 240)),
      hybridMaxShiftHours: hybridMaxShiftHours.clamp(1, 6),
      homeShowupLead: Duration(minutes: homeShowupLead.inMinutes.clamp(0, 240)),
      chosenSleep: clampSleepTarget(chosenSleep),
    );
  }

  UserSettings copyWith({
    DayTime? defaultBedTime,
    DayTime? defaultWakeTime,
    Duration? prepTime,
    Duration? commuteTime,
    int? hybridMaxShiftHours,
    Duration? homeShowupLead,
    Duration? chosenSleep,
  }) {
    return UserSettings(
      defaultBedTime: defaultBedTime ?? this.defaultBedTime,
      defaultWakeTime: defaultWakeTime ?? this.defaultWakeTime,
      prepTime: prepTime ?? this.prepTime,
      commuteTime: commuteTime ?? this.commuteTime,
      hybridMaxShiftHours: hybridMaxShiftHours ?? this.hybridMaxShiftHours,
      homeShowupLead: homeShowupLead ?? this.homeShowupLead,
      chosenSleep: chosenSleep ?? this.chosenSleep,
    ).normalized();
  }

  @override
  bool operator ==(Object other) {
    return other is UserSettings &&
        other.defaultBedTime == defaultBedTime &&
        other.defaultWakeTime == defaultWakeTime &&
        other.prepTime == prepTime &&
        other.commuteTime == commuteTime &&
        other.hybridMaxShiftHours == hybridMaxShiftHours &&
        other.homeShowupLead == homeShowupLead &&
        other.chosenSleep == chosenSleep;
  }

  @override
  int get hashCode => Object.hash(
    defaultBedTime,
    defaultWakeTime,
    prepTime,
    commuteTime,
    hybridMaxShiftHours,
    homeShowupLead,
    chosenSleep,
  );
}
