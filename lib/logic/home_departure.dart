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

/// Dawn report on the mode clock: wake early enough to prepare and travel,
/// and offer that sleep before the forced wake.
///
/// [clockZone] and [clockShift] default to the home base with no shift.
/// That is the fixed home night. Hybrid passes the same zone plus its
/// current shift. Local adaptation passes the station zone.
class HomeDepartureAdvisor {
  const HomeDepartureAdvisor();

  HomeDeparturePlan evaluate({
    required JetlagScheduleSnapshot schedule,
    required UserSettings settings,
    String? clockZone,
    Duration clockShift = Duration.zero,
  }) {
    final zone = clockZone == null || clockZone.trim().isEmpty
        ? schedule.referenceTimeZone
        : clockZone;
    final report = _bindingReport(schedule, settings, zone, clockShift);
    if (report == null) return HomeDeparturePlan.none;

    final night = _naturalNight(report, settings, zone, clockShift);
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

  /// Earlier of the pickup and show-up clocks that sit inside the mode night.
  /// Leaving is limited by whichever report arrives first.
  DateTime? _bindingReport(
    JetlagScheduleSnapshot schedule,
    UserSettings settings,
    String zone,
    Duration shift,
  ) {
    final candidates = <DateTime>[
      if (schedule.pickupUtc != null) schedule.pickupUtc!.toUtc(),
      if (schedule.showupUtc != null) schedule.showupUtc!.toUtc(),
    ];
    DateTime? chosen;
    for (final instant in candidates) {
      if (_naturalNight(instant, settings, zone, shift) == null) continue;
      if (chosen == null || instant.isBefore(chosen)) chosen = instant;
    }
    return chosen;
  }

  /// The mode night that contains [instant], or null when it is daytime
  /// on that clock. [shift] moves the home night the way Hybrid does.
  _Night? _naturalNight(
    DateTime instant,
    UserSettings settings,
    String zone,
    Duration shift,
  ) {
    final utc = instant.toUtc();
    final wall = wallClock(utc, zone);
    final today = DateTime(wall.year, wall.month, wall.day);
    final bedMinute = settings.defaultBedTime.minuteOfDay;
    final wakeMinute = settings.defaultWakeTime.minuteOfDay;
    for (final delta in const [-1, 0, 1]) {
      final day = DateTime(today.year, today.month, today.day + delta);
      final bedUtc = _at(zone, day, bedMinute, shift);
      var wakeUtc = _at(zone, day, wakeMinute, shift);
      if (!wakeUtc.isAfter(bedUtc)) {
        final next = DateTime(day.year, day.month, day.day + 1);
        wakeUtc = _at(zone, next, wakeMinute, shift);
      }
      if (!utc.isBefore(bedUtc) && utc.isBefore(wakeUtc)) {
        return _Night(bedUtc, wakeUtc);
      }
    }
    return null;
  }

  DateTime _at(String iana, DateTime day, int minuteOfDay, Duration shift) {
    return zonedUtc(
      iana: iana,
      year: day.year,
      month: day.month,
      day: day.day,
      hour: minuteOfDay ~/ 60,
      minute: minuteOfDay % 60,
      shift: shift,
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
