import 'arrival_order.dart';

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
    this.arrivalDeboard = const Duration(minutes: 30),
    this.hotelTransfer = const Duration(minutes: 60),
    this.afterHotelReady = const Duration(minutes: 60),
    this.arrivalOrder = ArrivalOrder.auto,
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

  /// Deboarding and entry after ramp arrival (STA).
  final Duration arrivalDeboard;

  /// Hotel transfer after deboarding.
  final Duration hotelTransfer;

  /// Shower and settle time after hotel arrival, before sleep can start.
  final Duration afterHotelReady;

  /// Meal vs rest order when the first post-arrival sleep sits close to STA.
  final ArrivalOrder arrivalOrder;

  /// Largest circadian move Hybrid mode will apply, in whole hours (1–6).
  final int hybridMaxShiftHours;

  /// How long before the outbound STD the crew shows up at home base,
  /// when a journey does not name its own show-up. Clamped to 0–240 minutes.
  final Duration homeShowupLead;

  /// Stored length behind [sleepTarget]. Clamped to 4–9 hours on 30-minute steps.
  final Duration chosenSleep;

  static const minSleepTarget = Duration(hours: 4);
  static const maxSleepTarget = Duration(hours: 9);
  static const minArrivalToSleep = Duration(hours: 1);
  static const maxArrivalToSleep = Duration(hours: 4);

  /// Deboard + transfer + after-hotel ready. Same numeric result as the old
  /// single [arrivalToSleep] setting (default 2 hours 30 minutes).
  Duration get arrivalToSleep =>
      arrivalDeboard + hotelTransfer + afterHotelReady;

  /// Deboard + hotel transfer. Meal-ready is STA + this delay.
  Duration get hotelArrivalDelay => arrivalDeboard + hotelTransfer;

  /// Hotel arrival = ramp arrival (STA) + deboard + transfer.
  DateTime hotelArrivalUtc(DateTime sta) =>
      sta.toUtc().add(hotelArrivalDelay);

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

  /// Keeps the post-arrival delay inside 1–4 hours, on a 15-minute step.
  static Duration clampArrivalToSleep(Duration value) {
    final minutes = value.inMinutes.clamp(
      minArrivalToSleep.inMinutes,
      maxArrivalToSleep.inMinutes,
    );
    final snapped = ((minutes / 15).round() * 15).clamp(
      minArrivalToSleep.inMinutes,
      maxArrivalToSleep.inMinutes,
    );
    return Duration(minutes: snapped.toInt());
  }

  /// Splits a total arrival-to-sleep delay 1:2:2 (deboard:transfer:ready)
  /// on 15-minute steps so the parts sum exactly to the clamped total.
  static ({Duration deboard, Duration transfer, Duration ready})
  splitArrivalToSleep(Duration total) {
    final minutes = clampArrivalToSleep(total).inMinutes;
    var deboard = _snapArrivalMinutes((minutes / 5).round());
    var transfer = _snapArrivalMinutes((minutes * 2 / 5).round());
    if (deboard + transfer > minutes) {
      transfer = (minutes - deboard) ~/ 15 * 15;
    }
    final ready = minutes - deboard - transfer;
    return (
      deboard: Duration(minutes: deboard),
      transfer: Duration(minutes: transfer),
      ready: Duration(minutes: ready),
    );
  }

  /// Clamps one arrival part so the three-part sum stays in 1–4 hours.
  static Duration clampArrivalPart(
    Duration part, {
    required Duration otherA,
    required Duration otherB,
  }) {
    final others = otherA.inMinutes + otherB.inMinutes;
    final lo = (minArrivalToSleep.inMinutes - others).clamp(0, maxArrivalToSleep.inMinutes);
    final hi = (maxArrivalToSleep.inMinutes - others).clamp(0, maxArrivalToSleep.inMinutes);
    final low = lo <= hi ? lo : hi;
    final high = lo <= hi ? hi : lo;
    final snapped = _snapArrivalMinutes(part.inMinutes).clamp(low, high);
    return Duration(minutes: snapped.toInt());
  }

  static int _snapArrivalMinutes(int minutes) {
    final clamped = minutes.clamp(0, maxArrivalToSleep.inMinutes);
    return ((clamped / 15).round() * 15).clamp(0, maxArrivalToSleep.inMinutes);
  }

  UserSettings normalized() {
    var deboard = Duration(minutes: _snapArrivalMinutes(arrivalDeboard.inMinutes));
    var transfer = Duration(minutes: _snapArrivalMinutes(hotelTransfer.inMinutes));
    var ready = Duration(minutes: _snapArrivalMinutes(afterHotelReady.inMinutes));
    final sum = deboard.inMinutes + transfer.inMinutes + ready.inMinutes;
    if (sum < minArrivalToSleep.inMinutes || sum > maxArrivalToSleep.inMinutes) {
      final parts = splitArrivalToSleep(Duration(minutes: sum));
      deboard = parts.deboard;
      transfer = parts.transfer;
      ready = parts.ready;
    }
    return UserSettings(
      defaultBedTime: defaultBedTime.normalized(),
      defaultWakeTime: defaultWakeTime.normalized(),
      prepTime: Duration(minutes: prepTime.inMinutes.clamp(0, 180)),
      commuteTime: Duration(minutes: commuteTime.inMinutes.clamp(0, 240)),
      arrivalDeboard: deboard,
      hotelTransfer: transfer,
      afterHotelReady: ready,
      arrivalOrder: arrivalOrder,
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
    Duration? arrivalDeboard,
    Duration? hotelTransfer,
    Duration? afterHotelReady,
    Duration? arrivalToSleep,
    ArrivalOrder? arrivalOrder,
    int? hybridMaxShiftHours,
    Duration? homeShowupLead,
    Duration? chosenSleep,
  }) {
    if (arrivalToSleep != null &&
        arrivalDeboard == null &&
        hotelTransfer == null &&
        afterHotelReady == null) {
      final parts = splitArrivalToSleep(arrivalToSleep);
      return UserSettings(
        defaultBedTime: defaultBedTime ?? this.defaultBedTime,
        defaultWakeTime: defaultWakeTime ?? this.defaultWakeTime,
        prepTime: prepTime ?? this.prepTime,
        commuteTime: commuteTime ?? this.commuteTime,
        arrivalDeboard: parts.deboard,
        hotelTransfer: parts.transfer,
        afterHotelReady: parts.ready,
        arrivalOrder: arrivalOrder ?? this.arrivalOrder,
        hybridMaxShiftHours: hybridMaxShiftHours ?? this.hybridMaxShiftHours,
        homeShowupLead: homeShowupLead ?? this.homeShowupLead,
        chosenSleep: chosenSleep ?? this.chosenSleep,
      ).normalized();
    }

    var nextDeboard = arrivalDeboard ?? this.arrivalDeboard;
    var nextTransfer = hotelTransfer ?? this.hotelTransfer;
    var nextReady = afterHotelReady ?? this.afterHotelReady;

    if (arrivalDeboard != null &&
        hotelTransfer == null &&
        afterHotelReady == null) {
      nextDeboard = clampArrivalPart(
        arrivalDeboard,
        otherA: this.hotelTransfer,
        otherB: this.afterHotelReady,
      );
    } else if (hotelTransfer != null &&
        arrivalDeboard == null &&
        afterHotelReady == null) {
      nextTransfer = clampArrivalPart(
        hotelTransfer,
        otherA: this.arrivalDeboard,
        otherB: this.afterHotelReady,
      );
    } else if (afterHotelReady != null &&
        arrivalDeboard == null &&
        hotelTransfer == null) {
      nextReady = clampArrivalPart(
        afterHotelReady,
        otherA: this.arrivalDeboard,
        otherB: this.hotelTransfer,
      );
    }

    return UserSettings(
      defaultBedTime: defaultBedTime ?? this.defaultBedTime,
      defaultWakeTime: defaultWakeTime ?? this.defaultWakeTime,
      prepTime: prepTime ?? this.prepTime,
      commuteTime: commuteTime ?? this.commuteTime,
      arrivalDeboard: nextDeboard,
      hotelTransfer: nextTransfer,
      afterHotelReady: nextReady,
      arrivalOrder: arrivalOrder ?? this.arrivalOrder,
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
        other.arrivalDeboard == arrivalDeboard &&
        other.hotelTransfer == hotelTransfer &&
        other.afterHotelReady == afterHotelReady &&
        other.arrivalOrder == arrivalOrder &&
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
    arrivalDeboard,
    hotelTransfer,
    afterHotelReady,
    arrivalOrder,
    hybridMaxShiftHours,
    homeShowupLead,
    chosenSleep,
  );
}
