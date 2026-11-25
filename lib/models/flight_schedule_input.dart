import '../logic/home_base_timezone.dart';
import 'bunk_shift.dart';
import 'flight_leg.dart';
import 'jetlag_schedule.dart';
import 'user_settings.dart';

/// One journey handed to the guide.
///
/// A journey is an outbound leg, a return leg, or both, plus an optional
/// home-base show-up and an optional layover pickup. Every instant is UTC.
///
/// The unnamed constructor builds a return-only journey. That is also how
/// JSON written by the previous layover record is read: those fields become
/// [returning], and [outbound] stays null. Both `pickup` and `showup` on that
/// record are layover-local clocks, so [homeShowupUtc] stays empty and
/// [layoverPickupUtc] is the earlier of the two. [toSnapshot] still feeds the
/// calculator the same pickup and show-up it received before this split.
class FlightScheduleInput {
  FlightScheduleInput({
    required String flightNumber,
    required String origin,
    required String destination,
    required String destinationTimeZone,
    required DateTime std,
    required DateTime sta,
    DateTime? pickup,
    DateTime? showup,
    this.crewRole = JetlagCrewRole.flightOps,
    this.blockMinutes = 11 * 60,
    this.referenceTimeZone = kJetlagFallbackHomeBase,
  }) : outbound = null,
       returning = FlightLeg(
         flightNumber: flightNumber,
         origin: origin,
         destination: destination,
         destinationTimeZone: destinationTimeZone,
         std: std,
         sta: sta,
       ),
       homeShowupUtc = null,
       layoverPickupUtc = _earlier(pickup, showup),
       _snapshotPickupUtc = pickup?.toUtc(),
       _snapshotShowupUtc = showup?.toUtc(),
       outboundBunk = null,
       returnBunk = null;

  FlightScheduleInput.journey({
    this.outbound,
    this.returning,
    DateTime? homeShowup,
    DateTime? layoverPickup,
    this.crewRole = JetlagCrewRole.flightOps,
    int? blockMinutes,
    this.referenceTimeZone = kJetlagFallbackHomeBase,
    this.outboundBunk,
    this.returnBunk,
  }) : homeShowupUtc = homeShowup?.toUtc(),
       layoverPickupUtc = layoverPickup?.toUtc(),
       _snapshotPickupUtc = layoverPickup?.toUtc(),
       _snapshotShowupUtc = homeShowup?.toUtc(),
       blockMinutes = blockMinutes ?? _blockOf(returning) {
    if (outbound == null && returning == null) {
      throw ArgumentError('A journey needs an outbound or a return leg.');
    }
  }

  /// Going out. Null when a saved layover record had no outbound sector.
  final FlightLeg? outbound;

  /// Coming back. Legacy records are stored entirely on this leg.
  final FlightLeg? returning;

  /// Report time at home, before the outbound departure. Empty when the crew
  /// has not entered one; [effectiveHomeShowupUtc] then uses the settings lead.
  final DateTime? homeShowupUtc;

  /// Pickup at the layover station.
  ///
  /// On a previously saved layover this is the earlier of that record's
  /// pickup and show-up. Both of those clocks were local to the layover.
  final DateTime? layoverPickupUtc;

  /// Pickup the calculator already consumed. Kept apart from
  /// [layoverPickupUtc] so a legacy file still round-trips both clocks.
  final DateTime? _snapshotPickupUtc;

  /// Show-up the calculator already consumed.
  final DateTime? _snapshotShowupUtc;

  final JetlagCrewRole crewRole;

  /// Bunk choice for the outbound leg. Null until the crew picks one.
  final BunkShift? outboundBunk;

  /// Bunk choice for the return leg.
  final BunkShift? returnBunk;

  /// Airborne minutes of the flight that leaves the layover.
  final int blockMinutes;

  final String referenceTimeZone;

  bool get returnOnly => outbound == null && returning != null;

  /// Fields the previous single-layover record exposed.
  ///
  /// They follow [returning] when it exists, so a legacy object still reports
  /// the same flight, airports, and instants as before.
  String get flightNumber => _surface.flightNumber;
  String get origin => _surface.origin;
  String get destination => _surface.destination;
  String get destinationTimeZone => _surface.destinationTimeZone;
  DateTime get stdUtc => _surface.stdUtc;
  DateTime get staUtc => _surface.staUtc;
  DateTime? get pickupUtc => _snapshotPickupUtc;
  DateTime? get showupUtc => _snapshotShowupUtc;

  /// Home-base show-up actually used for this journey.
  ///
  /// An entered [homeShowupUtc] wins. Otherwise this is the outbound STD
  /// minus [UserSettings.homeShowupLead]. With no outbound leg and no entered
  /// show-up there is nothing to report.
  DateTime? effectiveHomeShowupUtc(UserSettings settings) {
    final entered = homeShowupUtc;
    if (entered != null) return entered.toUtc();
    final std = outbound?.stdUtc;
    if (std == null) return null;
    return std.toUtc().subtract(settings.normalized().homeShowupLead);
  }

  FlightLeg get _surface => returning ?? outbound!;

  /// Layover window the guide calculator already understands.
  ///
  /// Return-only journeys, including every previously saved record, pass their
  /// stored arrival and departure through unchanged. A round trip uses the
  /// outbound arrival as STA and the return departure as STD.
  JetlagScheduleSnapshot toSnapshot() {
    final back = returning;
    final out = outbound;
    if (out != null && back != null) {
      return JetlagScheduleSnapshot(
        stationLabel: out.destination,
        originLabel: out.origin,
        localTimeZone: out.destinationTimeZone,
        staUtc: out.staUtc,
        stdUtc: back.stdUtc,
        pickupUtc: pickupUtc,
        showupUtc: showupUtc,
        flightNumber: back.flightNumber,
        crewRole: crewRole,
        blockMinutes: blockMinutes,
        referenceTimeZone: referenceTimeZone,
      );
    }
    final leg = _surface;
    return JetlagScheduleSnapshot(
      stationLabel: leg.destination,
      originLabel: leg.origin,
      localTimeZone: leg.destinationTimeZone,
      staUtc: leg.staUtc,
      stdUtc: leg.stdUtc,
      pickupUtc: pickupUtc,
      showupUtc: showupUtc,
      flightNumber: leg.flightNumber,
      crewRole: crewRole,
      blockMinutes: blockMinutes,
      referenceTimeZone: referenceTimeZone,
    );
  }

  factory FlightScheduleInput.fromSnapshot(JetlagScheduleSnapshot snapshot) {
    return FlightScheduleInput(
      flightNumber: snapshot.flightNumber,
      origin: snapshot.originLabel,
      destination: snapshot.stationLabel,
      destinationTimeZone: snapshot.localTimeZone,
      referenceTimeZone: snapshot.referenceTimeZone,
      std: snapshot.stdUtc,
      sta: snapshot.staUtc,
      pickup: snapshot.pickupUtc,
      showup: snapshot.showupUtc,
      crewRole: snapshot.crewRole,
      blockMinutes: snapshot.blockMinutes,
    );
  }

  /// JSON object. Every instant is a UTC ISO-8601 string.
  ///
  /// A return-only journey keeps the previous key layout so existing files
  /// round-trip. A journey with an outbound leg uses version 2.
  Map<String, Object?> toJson() {
    if (returnOnly) return _legacyJson();
    return {
      'version': 2,
      'outbound': outbound?.toJson(),
      'returning': returning?.toJson(),
      'homeShowup': homeShowupUtc?.toUtc().toIso8601String(),
      'layoverPickup': layoverPickupUtc?.toUtc().toIso8601String(),
      if (outboundBunk != null) 'outboundBunk': outboundBunk!.name,
      if (returnBunk != null) 'returnBunk': returnBunk!.name,
      'crewRole': crewRole.name,
      'blockMinutes': blockMinutes,
      'referenceTimeZone': referenceTimeZone,
    };
  }

  Map<String, Object?> _legacyJson() {
    return {
      'flightNumber': flightNumber,
      'origin': origin,
      'destination': destination,
      'destinationTimeZone': destinationTimeZone,
      'std': stdUtc.toUtc().toIso8601String(),
      'sta': staUtc.toUtc().toIso8601String(),
      'pickup': pickupUtc?.toUtc().toIso8601String(),
      'showup': showupUtc?.toUtc().toIso8601String(),
      'crewRole': crewRole.name,
      'blockMinutes': blockMinutes,
      'referenceTimeZone': referenceTimeZone,
    };
  }

  static FlightScheduleInput? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    if (_isJourney(json)) return _parseJourney(json);
    return _parseLegacy(json);
  }

  static bool _isJourney(Map<String, Object?> json) {
    if (json['version'] == 2) return true;
    return json.containsKey('outbound') || json.containsKey('returning');
  }

  static FlightScheduleInput? _parseLegacy(Map<String, Object?> json) {
    final origin = _code(json['origin']);
    final destination = _code(json['destination']);
    final zone = _text(json['destinationTimeZone']);
    final sta = _utc(json['sta']);
    final std = _utc(json['std']);
    if (origin == null ||
        destination == null ||
        zone == null ||
        sta == null ||
        std == null ||
        !std.isAfter(sta)) {
      return null;
    }
    final flight = _text(json['flightNumber']) ?? '';
    final reference =
        _text(json['referenceTimeZone']) ?? kJetlagFallbackHomeBase;
    final block = json['blockMinutes'];
    return FlightScheduleInput(
      flightNumber: flight,
      origin: origin,
      destination: destination,
      destinationTimeZone: zone,
      referenceTimeZone: reference,
      std: std,
      sta: sta,
      pickup: _utc(json['pickup']),
      showup: _utc(json['showup']),
      crewRole: json['crewRole'] == JetlagCrewRole.cabin.name
          ? JetlagCrewRole.cabin
          : JetlagCrewRole.flightOps,
      blockMinutes: block is int ? block : 11 * 60,
    );
  }

  static FlightScheduleInput? _parseJourney(Map<String, Object?> json) {
    final outbound = json['outbound'] == null
        ? null
        : FlightLeg.tryParse(json['outbound']);
    final returning = json['returning'] == null
        ? null
        : FlightLeg.tryParse(json['returning']);
    if (json['outbound'] != null && outbound == null) return null;
    if (json['returning'] != null && returning == null) return null;
    if (outbound == null && returning == null) return null;
    final reference =
        _text(json['referenceTimeZone']) ?? kJetlagFallbackHomeBase;
    final block = json['blockMinutes'];
    return FlightScheduleInput.journey(
      outbound: outbound,
      returning: returning,
      homeShowup: _utc(json['homeShowup']),
      layoverPickup: _utc(json['layoverPickup']),
      crewRole: json['crewRole'] == JetlagCrewRole.cabin.name
          ? JetlagCrewRole.cabin
          : JetlagCrewRole.flightOps,
      blockMinutes: block is int ? block : null,
      referenceTimeZone: reference,
      outboundBunk: _bunk(json['outboundBunk']),
      returnBunk: _bunk(json['returnBunk']),
    );
  }

  /// Same journey with a new layover pickup, keeping the calculator clocks
  /// a legacy file already exposed.
  FlightScheduleInput withLayoverPickup(DateTime pickup) {
    if (returnOnly) {
      return FlightScheduleInput.fromSnapshot(
        toSnapshot().copyWith(pickupUtc: pickup.toUtc()),
      );
    }
    return FlightScheduleInput.journey(
      outbound: outbound,
      returning: returning,
      homeShowup: homeShowupUtc,
      layoverPickup: pickup,
      crewRole: crewRole,
      blockMinutes: blockMinutes,
      referenceTimeZone: referenceTimeZone,
      outboundBunk: outboundBunk,
      returnBunk: returnBunk,
    );
  }
}

int _blockOf(FlightLeg? returning) {
  if (returning == null || !returning.arrivesAfterDeparture) return 11 * 60;
  final minutes = returning.staUtc.difference(returning.stdUtc).inMinutes;
  if (minutes < 30) return 30;
  if (minutes > 20 * 60) return 20 * 60;
  return minutes;
}

String? _text(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

String? _code(Object? raw) {
  final text = _text(raw);
  if (text == null) return null;
  return text.toUpperCase();
}

BunkShift? _bunk(Object? raw) {
  if (raw is! String) return null;
  for (final shift in BunkShift.values) {
    if (shift.name == raw) return shift;
  }
  return null;
}

DateTime? _utc(Object? raw) {
  final text = _text(raw);
  if (text == null) return null;
  return DateTime.tryParse(text)?.toUtc();
}

/// Earlier of two layover clocks. A missing side leaves the other one.
DateTime? _earlier(DateTime? left, DateTime? right) {
  final a = left?.toUtc();
  final b = right?.toUtc();
  if (a == null) return b;
  if (b == null) return a;
  return a.isBefore(b) ? a : b;
}
