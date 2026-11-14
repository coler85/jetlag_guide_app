import 'logic/home_base_timezone.dart';
import 'models/flight_schedule_input.dart';
import 'models/jetlag_schedule.dart';

/// Demo layover around [now], so the now-line and pickup countdown are visible
/// without a roster or a deep link.
///
/// STA is the inbound arrival and STD is the later outbound departure.
FlightScheduleInput sampleFlightSchedule({DateTime? now}) {
  final clock = (now ?? DateTime.now()).toUtc();
  return FlightScheduleInput(
    flightNumber: 'KE017',
    origin: 'ICN',
    destination: 'LAX',
    destinationTimeZone: 'America/Los_Angeles',
    referenceTimeZone: kJetlagFallbackHomeBase,
    sta: clock.subtract(const Duration(hours: 10)),
    std: clock.add(const Duration(hours: 16)),
    pickup: clock.add(const Duration(hours: 12)),
    showup: clock.add(const Duration(hours: 14)),
    crewRole: JetlagCrewRole.flightOps,
    blockMinutes: 11 * 60,
  );
}

JetlagScheduleSnapshot sampleJetlagSchedule({DateTime? now}) {
  return sampleFlightSchedule(now: now).toSnapshot();
}
