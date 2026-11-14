import 'logic/home_base_timezone.dart';
import 'models/jetlag_schedule.dart';

/// Demo layover around [now], so the now-line and pickup countdown are visible
/// without reading the roster store.
JetlagScheduleSnapshot sampleJetlagSchedule({DateTime? now}) {
  final clock = (now ?? DateTime.now()).toUtc();
  return JetlagScheduleSnapshot(
    stationLabel: 'LAX',
    localTimeZone: 'America/Los_Angeles',
    referenceTimeZone: kJetlagFallbackHomeBase,
    staUtc: clock.subtract(const Duration(hours: 10)),
    stdUtc: clock.add(const Duration(hours: 16)),
    pickupUtc: clock.add(const Duration(hours: 12)),
    showupUtc: clock.add(const Duration(hours: 14)),
    flightNumber: 'KE017',
    crewRole: JetlagCrewRole.flightOps,
    blockMinutes: 11 * 60,
  );
}
