import '../models/jetlag_schedule.dart';
import '../models/user_settings.dart';
import 'jetlag_clock.dart';
import 'sleep_constants.dart';

/// What to do with the night before a report time that lands inside the
/// crew's usual sleep.
class HomeDeparturePlan {
  const HomeDeparturePlan({
    required this.applies,
    this.reportUtc,
    this.forcedWakeUtc,
    this.naturalBedUtc,
    this.naturalWakeUtc,
    this.recommendedStartUtc,
    this.recommendedEndUtc,
    this.shortfall = Duration.zero,
  });

  static const none = HomeDeparturePlan(applies: false);

  final bool applies;

  /// Pickup or show-up that falls inside the usual night, in UTC.
  final DateTime? reportUtc;

  /// [reportUtc] minus prep and commute.
  final DateTime? forcedWakeUtc;

  /// Usual bedtime and wake that contain [reportUtc], on the home-base clock.
  final DateTime? naturalBedUtc;
  final DateTime? naturalWakeUtc;

  /// Usual-length night pulled forward so it ends at [forcedWakeUtc].
  final DateTime? recommendedStartUtc;
  final DateTime? recommendedEndUtc;

  /// Usual night minus the hours still available if bedtime stays put.
  /// Positive when the early wake cuts sleep. Zero when the night still fits.
  final Duration shortfall;
}

/// Home-base dawn report: wake early enough to prepare and travel, and
/// offer that sleep before the forced wake.
class HomeDepartureAdvisor {
  const HomeDepartureAdvisor();

  HomeDeparturePlan evaluate({
    required JetlagScheduleSnapshot schedule,
    required UserSettings settings,
  }) {
    final home = schedule.referenceTimeZone;
    final report = _bindingReport(schedule, settings, home);
    if (report == null) return HomeDeparturePlan.none;

    final night = _naturalNight(report, settings, home);
    if (night == null) return HomeDeparturePlan.none;

    final lead = settings.prepTime + settings.commuteTime;
    final forcedWake = report.toUtc().subtract(lead);
    if (!forcedWake.isBefore(night.wakeUtc)) return HomeDeparturePlan.none;

    final target = settings.sleepTarget;
    if (target <= Duration.zero) return HomeDeparturePlan.none;

    final keptEnd = forcedWake.isBefore(night.bedUtc)
        ? night.bedUtc
        : forcedWake;
    final kept = keptEnd.difference(night.bedUtc);
    final missing = target - kept;
    final shortfall = missing.isNegative ? Duration.zero : missing;

    return HomeDeparturePlan(
      applies: true,
      reportUtc: report.toUtc(),
      forcedWakeUtc: forcedWake,
      naturalBedUtc: night.bedUtc,
      naturalWakeUtc: night.wakeUtc,
      recommendedStartUtc: forcedWake.subtract(target),
      recommendedEndUtc: forcedWake,
      shortfall: shortfall,
    );
  }

  /// Wake for the last sleep before departure.
  ///
  /// [clockFallsInSleep] does not apply. A pickup is the anchor only when one
  /// 90-minute cycle can still start at or after arrival plus
  /// [UserSettings.arrivalToSleep]. Otherwise the anchor is
  /// departure − show-up lead − prep − commute.
  DateTime? preDepartureWake({
    required JetlagScheduleSnapshot schedule,
    required UserSettings settings,
  }) {
    final sta = schedule.staUtc.toUtc();
    final std = schedule.stdUtc.toUtc();
    if (!std.isAfter(sta)) return null;
    final lead = settings.prepTime + settings.commuteTime;
    final floor = sta.add(settings.arrivalToSleep);
    final pickup = schedule.pickupUtc?.toUtc();
    if (pickup != null) {
      final fromPickup = pickup.subtract(lead);
      final oneCycleStart = fromPickup.subtract(kSleepCycle);
      if (!oneCycleStart.isBefore(floor)) return fromPickup;
    }
    return std.subtract(settings.homeShowupLead).subtract(lead);
  }

  /// Earlier of the pickup and show-up clocks that sit inside the usual night.
  /// Leaving home is limited by whichever report arrives first.
  DateTime? _bindingReport(
    JetlagScheduleSnapshot schedule,
    UserSettings settings,
    String homeIana,
  ) {
    final candidates = <DateTime>[
      if (schedule.pickupUtc != null) schedule.pickupUtc!.toUtc(),
      if (schedule.showupUtc != null) schedule.showupUtc!.toUtc(),
    ];
    DateTime? chosen;
    for (final instant in candidates) {
      if (!_inUsualSleep(instant, settings, homeIana)) continue;
      if (chosen == null || instant.isBefore(chosen)) chosen = instant;
    }
    return chosen;
  }

  bool _inUsualSleep(DateTime instant, UserSettings settings, String homeIana) {
    final wall = wallClock(instant, homeIana);
    return clockFallsInSleep(
      wall.hour * 60 + wall.minute,
      settings.defaultBedTime.minuteOfDay,
      settings.defaultWakeTime.minuteOfDay,
    );
  }

  _Night? _naturalNight(
    DateTime instant,
    UserSettings settings,
    String homeIana,
  ) {
    final wall = wallClock(instant, homeIana);
    final minute = wall.hour * 60 + wall.minute;
    final bedMinute = settings.defaultBedTime.minuteOfDay;
    final wakeMinute = settings.defaultWakeTime.minuteOfDay;
    if (!clockFallsInSleep(minute, bedMinute, wakeMinute)) return null;

    final today = DateTime(wall.year, wall.month, wall.day);
    final bedDay = bedMinute > wakeMinute && minute < bedMinute
        ? today.subtract(const Duration(days: 1))
        : today;
    final bedUtc = _at(homeIana, bedDay, bedMinute);
    var wakeUtc = _at(homeIana, bedDay, wakeMinute);
    if (!wakeUtc.isAfter(bedUtc)) {
      wakeUtc = _at(homeIana, bedDay.add(const Duration(days: 1)), wakeMinute);
    }
    return _Night(bedUtc, wakeUtc);
  }

  DateTime _at(String iana, DateTime day, int minuteOfDay) {
    return zonedUtc(
      iana: iana,
      year: day.year,
      month: day.month,
      day: day.day,
      hour: minuteOfDay ~/ 60,
      minute: minuteOfDay % 60,
    );
  }
}

/// True when [minute] sits in the bedtime→wake window, including overnight.
bool clockFallsInSleep(int minute, int bedMinute, int wakeMinute) {
  if (bedMinute == wakeMinute) return false;
  if (bedMinute < wakeMinute) {
    return minute >= bedMinute && minute < wakeMinute;
  }
  return minute >= bedMinute || minute < wakeMinute;
}

class _Night {
  const _Night(this.bedUtc, this.wakeUtc);

  final DateTime bedUtc;
  final DateTime wakeUtc;
}
