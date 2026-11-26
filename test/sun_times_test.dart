import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/data/airport_zones.dart';
import 'package:jetlag_guide_app/logic/sun_times.dart';

/// Published UTC sunrise and sunset for the airport coordinates.
/// Compared with https://api.sunrise-sunset.org for the same latitude,
/// longitude, and calendar date (zenith 90.833°).
void main() {
  test('Seoul, Amsterdam, and LA stay within five minutes', () {
    final icn = placeForAirport('ICN')!;
    final ams = placeForAirport('AMS')!;
    final lax = placeForAirport('LAX')!;

    _expectSun(
      icn,
      DateTime.utc(2026, 1, 15),
      '2026-01-14T22:47:35Z',
      '2026-01-15T08:39:22Z',
    );
    _expectSun(
      icn,
      DateTime.utc(2026, 6, 21, 18, 40),
      '2026-06-20T20:13:22Z',
      '2026-06-21T10:58:30Z',
    );
    _expectSun(
      ams,
      DateTime.utc(2026, 3, 20),
      '2026-03-20T05:43:04Z',
      '2026-03-20T17:53:43Z',
    );
    _expectSun(
      ams,
      DateTime.utc(2026, 6, 21),
      '2026-06-21T03:18:53Z',
      '2026-06-21T20:06:38Z',
    );
    _expectSun(
      lax,
      DateTime.utc(2026, 1, 15),
      '2026-01-15T14:58:30Z',
      '2026-01-16T01:07:48Z',
    );
    _expectSun(
      lax,
      DateTime.utc(2026, 12, 21),
      '2026-12-21T14:55:02Z',
      '2026-12-22T00:48:41Z',
    );
  });

  test('polar day and polar night have no sunrise or sunset', () {
    const latitude = 78.2232;
    const longitude = 15.6267;
    for (final day in [DateTime.utc(2026, 6, 21), DateTime.utc(2026, 12, 21)]) {
      final times = sunTimes(
        latitude: latitude,
        longitude: longitude,
        day: day,
      );
      expect(times.sunriseUtc, isNull, reason: '$day');
      expect(times.sunsetUtc, isNull, reason: '$day');
    }
  });
}

void _expectSun(
  AirportPlace place,
  DateTime day,
  String sunrise,
  String sunset,
) {
  final times = sunTimes(
    latitude: place.latitude,
    longitude: place.longitude,
    day: day,
  );
  expect(_gap(times.sunriseUtc, sunrise), lessThanOrEqualTo(5 * 60));
  expect(_gap(times.sunsetUtc, sunset), lessThanOrEqualTo(5 * 60));
}

int _gap(DateTime? actual, String expected) {
  expect(actual, isNotNull);
  return actual!.difference(DateTime.parse(expected)).inSeconds.abs();
}
