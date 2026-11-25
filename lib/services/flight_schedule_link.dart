import 'package:timezone/timezone.dart' as tz;

import '../logic/jetlag_clock.dart';
import '../models/flight_schedule_input.dart';
import '../models/jetlag_schedule.dart';

/// `jetlagguide://schedule` payload from KE Roster or any other launcher.
///
/// Required query keys: `origin`, `destination`, `tz`, `std`, `sta`.
/// Instants are ISO-8601. Optional: `flight`, `pickup`, `showup`, `block`
/// (minutes), `role` (`flightOps` or `cabin`).
class FlightScheduleLink {
  const FlightScheduleLink._();

  static const scheme = 'jetlagguide';
  static const host = 'schedule';

  static FlightScheduleInput? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != scheme || uri.host != host) return null;
    final query = uri.queryParameters;
    final origin = _code(query['origin']);
    final destination = _code(query['destination']);
    final zone = (query['tz'] ?? '').trim();
    final sta = DateTime.tryParse(query['sta'] ?? '')?.toUtc();
    final std = DateTime.tryParse(query['std'] ?? '')?.toUtc();
    if (origin == null || destination == null || sta == null || std == null) {
      return null;
    }
    if (!_knownZone(zone) || !std.isAfter(sta)) return null;

    final flight = (query['flight'] ?? '').trim().toUpperCase();
    return FlightScheduleInput(
      flightNumber: flight,
      origin: origin,
      destination: destination,
      destinationTimeZone: zone,
      std: std,
      sta: sta,
      pickup: _inside(query['pickup'], sta, std),
      showup: _inside(query['showup'], sta, std),
      crewRole: query['role'] == JetlagCrewRole.cabin.name
          ? JetlagCrewRole.cabin
          : JetlagCrewRole.flightOps,
      blockMinutes: _block(query['block']),
    );
  }

  static String? _code(String? raw) {
    final code = (raw ?? '').trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3,4}$').hasMatch(code)) return null;
    return code;
  }

  static bool _knownZone(String iana) {
    if (iana.isEmpty) return false;
    try {
      ensureJetlagTimeZones();
      tz.getLocation(iana);
      return true;
    } catch (_) {
      return false;
    }
  }

  static DateTime? _inside(String? raw, DateTime sta, DateTime std) {
    final instant = DateTime.tryParse(raw ?? '')?.toUtc();
    if (instant == null) return null;
    if (!instant.isAfter(sta) || !instant.isBefore(std)) return null;
    return instant;
  }

  static int _block(String? raw) {
    final value = int.tryParse(raw ?? '');
    if (value == null) return 11 * 60;
    if (value < 30) return 30;
    if (value > 20 * 60) return 20 * 60;
    return value;
  }
}
