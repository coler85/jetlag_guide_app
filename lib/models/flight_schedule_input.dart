import '../logic/home_base_timezone.dart';
import 'jetlag_schedule.dart';

/// Schedule facts pushed in by another app or a deep link.
///
/// This type does not depend on Flutter or the guide's state objects.
/// Every instant is stored in UTC.
class FlightScheduleInput {
  FlightScheduleInput({
    required this.flightNumber,
    required this.origin,
    required this.destination,
    required this.destinationTimeZone,
    required DateTime std,
    required DateTime sta,
    DateTime? pickup,
    DateTime? showup,
    this.crewRole = JetlagCrewRole.flightOps,
    this.blockMinutes = 11 * 60,
    this.referenceTimeZone = kJetlagFallbackHomeBase,
  }) : stdUtc = std.toUtc(),
       staUtc = sta.toUtc(),
       pickupUtc = pickup?.toUtc(),
       showupUtc = showup?.toUtc();

  final String flightNumber;
  final String origin;
  final String destination;

  /// IANA zone of [destination].
  final String destinationTimeZone;

  final DateTime stdUtc;
  final DateTime staUtc;
  final DateTime? pickupUtc;
  final DateTime? showupUtc;
  final JetlagCrewRole crewRole;
  final int blockMinutes;
  final String referenceTimeZone;

  /// Layover snapshot the guide calculator already understands.
  ///
  /// [destination] is the station whose local clock the timeline shows.
  JetlagScheduleSnapshot toSnapshot() {
    return JetlagScheduleSnapshot(
      stationLabel: destination,
      originLabel: origin,
      localTimeZone: destinationTimeZone,
      staUtc: staUtc,
      stdUtc: stdUtc,
      pickupUtc: pickupUtc,
      showupUtc: showupUtc,
      flightNumber: flightNumber,
      crewRole: crewRole,
      blockMinutes: blockMinutes,
      referenceTimeZone: referenceTimeZone,
    );
  }
}
