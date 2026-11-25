/// One flight: departure, arrival, and the airports at each end.
///
/// [stdUtc] is when it leaves [origin]. [staUtc] is when it lands at
/// [destination]. Both instants are UTC.
class FlightLeg {
  FlightLeg({
    required this.flightNumber,
    required this.origin,
    required this.destination,
    required this.destinationTimeZone,
    required DateTime std,
    required DateTime sta,
    this.originTimeZone = '',
  }) : stdUtc = std.toUtc(),
       staUtc = sta.toUtc();

  final String flightNumber;
  final String origin;
  final String destination;

  /// IANA zone of [origin]. Empty until a zone is known.
  final String originTimeZone;

  /// IANA zone of [destination].
  final String destinationTimeZone;

  final DateTime stdUtc;
  final DateTime staUtc;

  /// True when this leg is a flown sector, not a legacy layover window.
  bool get arrivesAfterDeparture => staUtc.isAfter(stdUtc);

  Map<String, Object?> toJson() {
    return {
      'flightNumber': flightNumber,
      'origin': origin,
      'destination': destination,
      'originTimeZone': originTimeZone,
      'destinationTimeZone': destinationTimeZone,
      'std': stdUtc.toUtc().toIso8601String(),
      'sta': staUtc.toUtc().toIso8601String(),
    };
  }

  /// A stored sector. [sta] must be after [std].
  static FlightLeg? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    final origin = _code(json['origin']);
    final destination = _code(json['destination']);
    final zone = _text(json['destinationTimeZone']);
    final std = _utc(json['std']);
    final sta = _utc(json['sta']);
    if (origin == null ||
        destination == null ||
        zone == null ||
        std == null ||
        sta == null ||
        !sta.isAfter(std)) {
      return null;
    }
    return FlightLeg(
      flightNumber: _text(json['flightNumber']) ?? '',
      origin: origin,
      destination: destination,
      originTimeZone: _text(json['originTimeZone']) ?? '',
      destinationTimeZone: zone,
      std: std,
      sta: sta,
    );
  }
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

DateTime? _utc(Object? raw) {
  final text = _text(raw);
  if (text == null) return null;
  return DateTime.tryParse(text)?.toUtc();
}
