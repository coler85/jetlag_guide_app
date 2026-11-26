import 'dart:math' as math;

/// Sunrise and sunset on one calendar day, both as UTC instants.
///
/// A null edge means the sun does not cross the horizon that way
/// (midnight sun or polar night).
class SunTimes {
  const SunTimes({this.sunriseUtc, this.sunsetUtc});

  final DateTime? sunriseUtc;
  final DateTime? sunsetUtc;
}

/// Sunrise and sunset at [latitude] and [longitude] on the calendar [day].
///
/// [latitude] is degrees north and [longitude] is degrees east. Only the
/// year, month, and day of [day] are used. The instants follow the NOAA
/// general solar equations with the standard 90.833° zenith. No package and
/// no network are used.
SunTimes sunTimes({
  required double latitude,
  required double longitude,
  required DateTime day,
}) {
  if (!latitude.isFinite || !longitude.isFinite) {
    return const SunTimes();
  }
  final jd = _julianDay(day.year, day.month, day.day);
  return SunTimes(
    sunriseUtc: _eventUtc(day, jd, latitude, longitude, rise: true),
    sunsetUtc: _eventUtc(day, jd, latitude, longitude, rise: false),
  );
}

DateTime? _eventUtc(
  DateTime day,
  double julianDay,
  double latitude,
  double longitude, {
  required bool rise,
}) {
  final first = _minutesFromMidnight(
    rise: rise,
    julianDay: julianDay,
    latitude: latitude,
    longitude: longitude,
  );
  if (first == null) return null;
  var minutes = first;
  final refined = _minutesFromMidnight(
    rise: rise,
    julianDay: julianDay + minutes / 1440.0,
    latitude: latitude,
    longitude: longitude,
  );
  if (refined != null) {
    minutes = refined;
    final again = _minutesFromMidnight(
      rise: rise,
      julianDay: julianDay + minutes / 1440.0,
      latitude: latitude,
      longitude: longitude,
    );
    if (again != null) minutes = again;
  }
  final midnight = DateTime.utc(day.year, day.month, day.day);
  return midnight.add(Duration(microseconds: (minutes * 60000000).round()));
}

/// Minutes after 00:00 UTC on the Julian day, or null when the sun stays
/// above or below the horizon.
double? _minutesFromMidnight({
  required bool rise,
  required double julianDay,
  required double latitude,
  required double longitude,
}) {
  final t = (julianDay - 2451545.0) / 36525.0;
  final position = _sunPosition(t);
  final lat = _radians(latitude);
  final dec = _radians(position.declination);
  final cosLat = math.cos(lat);
  final cosDec = math.cos(dec);
  if (cosLat.abs() < 1e-8 || cosDec.abs() < 1e-8) return null;
  final argument =
      math.cos(_radians(90.833)) / (cosLat * cosDec) -
      math.tan(lat) * math.tan(dec);
  if (argument < -1 || argument > 1) return null;
  final hourAngle = rise ? math.acos(argument) : -math.acos(argument);
  final delta = longitude + _degrees(hourAngle);
  return 720 - 4.0 * delta - position.equationOfTime;
}

({double declination, double equationOfTime}) _sunPosition(double t) {
  final meanLong = _wrap360(280.46646 + t * (36000.76983 + 0.0003032 * t));
  final anomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t);
  final eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
  final anomalyRad = _radians(anomaly);
  final center =
      math.sin(anomalyRad) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
      math.sin(2 * anomalyRad) * (0.019993 - 0.000101 * t) +
      math.sin(3 * anomalyRad) * 0.000289;
  final omega = 125.04 - 1934.136 * t;
  final apparent =
      meanLong + center - 0.00569 - 0.00478 * math.sin(_radians(omega));
  final seconds = 21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813));
  final meanObliquity = 23.0 + (26.0 + seconds / 60.0) / 60.0;
  final obliquity = meanObliquity + 0.00256 * math.cos(_radians(omega));
  final declination = _degrees(
    math.asin(math.sin(_radians(obliquity)) * math.sin(_radians(apparent))),
  );
  final y = math.tan(_radians(obliquity) / 2.0);
  final yy = y * y;
  final longRad = _radians(meanLong);
  final equation = _degrees(
    yy * math.sin(2 * longRad) -
        2 * eccentricity * math.sin(anomalyRad) +
        4 * eccentricity * yy * math.sin(anomalyRad) * math.cos(2 * longRad) -
        0.5 * yy * yy * math.sin(4 * longRad) -
        1.25 * eccentricity * eccentricity * math.sin(2 * anomalyRad),
  );
  return (declination: declination, equationOfTime: equation * 4.0);
}

double _julianDay(int year, int month, int day) {
  var y = year;
  var m = month;
  if (m <= 2) {
    y -= 1;
    m += 12;
  }
  final century = y ~/ 100;
  final gregorian = 2 - century + (century ~/ 4);
  return (365.25 * (y + 4716)).floor() +
      (30.6001 * (m + 1)).floor() +
      day +
      gregorian -
      1524.5;
}

double _wrap360(double degrees) {
  final wrapped = degrees % 360.0;
  return wrapped < 0 ? wrapped + 360.0 : wrapped;
}

double _radians(double degrees) => degrees * math.pi / 180.0;

double _degrees(double radians) => radians * 180.0 / math.pi;
