import '../logic/home_base_timezone.dart';

/// Layover facts handed in from outside this module.
///
/// STA, STD, station, and pickup never come from the roster database.
/// A future standalone app can build the same snapshot on its own.
class JetlagScheduleSnapshot {
  const JetlagScheduleSnapshot({
    required this.stationLabel,
    required this.localTimeZone,
    required this.staUtc,
    required this.stdUtc,
    this.pickupUtc,
    this.showupUtc,
    this.flightNumber = '',
    this.crewRole = JetlagCrewRole.flightOps,
    this.blockMinutes = 11 * 60,
    this.referenceTimeZone = kJetlagFallbackHomeBase,
  });

  /// Arrival station, for example `LAX`. A label, not a database key.
  final String stationLabel;

  /// IANA zone of [stationLabel].
  final String localTimeZone;

  /// Inbound arrival (STA).
  final DateTime staUtc;

  /// Outbound departure (STD).
  final DateTime stdUtc;

  final DateTime? pickupUtc;
  final DateTime? showupUtc;
  final String flightNumber;
  final JetlagCrewRole crewRole;

  /// Outbound block, used only to place in-flight bunk windows.
  final int blockMinutes;

  /// Clock the crew treats as home. The guide replaces this with the saved
  /// home base before it builds a timeline.
  final String referenceTimeZone;

  String get key =>
      '$stationLabel|${staUtc.toUtc().toIso8601String()}|${stdUtc.toUtc().toIso8601String()}';

  JetlagScheduleSnapshot copyWith({
    String? stationLabel,
    String? localTimeZone,
    DateTime? staUtc,
    DateTime? stdUtc,
    DateTime? pickupUtc,
    bool clearPickup = false,
    DateTime? showupUtc,
    String? flightNumber,
    JetlagCrewRole? crewRole,
    int? blockMinutes,
    String? referenceTimeZone,
  }) {
    return JetlagScheduleSnapshot(
      stationLabel: stationLabel ?? this.stationLabel,
      localTimeZone: localTimeZone ?? this.localTimeZone,
      staUtc: staUtc ?? this.staUtc,
      stdUtc: stdUtc ?? this.stdUtc,
      pickupUtc: clearPickup ? null : (pickupUtc ?? this.pickupUtc),
      showupUtc: showupUtc ?? this.showupUtc,
      flightNumber: flightNumber ?? this.flightNumber,
      crewRole: crewRole ?? this.crewRole,
      blockMinutes: blockMinutes ?? this.blockMinutes,
      referenceTimeZone: referenceTimeZone ?? this.referenceTimeZone,
    );
  }
}

enum JetlagCrewRole {
  flightOps,
  cabin;

  String get label {
    switch (this) {
      case JetlagCrewRole.flightOps:
        return '운항';
      case JetlagCrewRole.cabin:
        return '객실';
    }
  }
}
