import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/data/airport_zones.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(ensureJetlagTimeZones);

  test('every listed airport has a real zone and coordinates', () {
    expect(airportPlaces.length, 309);
    expect(airportZones.length, airportPlaces.length);
    for (final entry in airportPlaces.entries) {
      final place = entry.value;
      expect(entry.key, entry.key.toUpperCase());
      expect(entry.key.length, 3);
      expect(place.latitude, inInclusiveRange(-90, 90));
      expect(place.longitude, inInclusiveRange(-180, 180));
      expect(airportZones[entry.key], place.zone);
      expect(
        () => tz.getLocation(place.zone),
        returnsNormally,
        reason: '${entry.key} -> ${place.zone}',
      );
    }
    expect(placeForAirport('ICN')?.latitude, closeTo(37.469101, 0.000001));
    expect(placeForAirport('ICN')?.longitude, closeTo(126.450996, 0.000001));
    expect(placeForAirport('fru')?.latitude, closeTo(43.061298, 0.000001));
    expect(placeForAirport('FRU')?.longitude, closeTo(74.4776, 0.000001));
    expect(placeForAirport('REP')?.latitude, closeTo(13.36974, 0.000001));
    expect(placeForAirport('REP')?.longitude, closeTo(104.223831, 0.000001));
    expect(placeForAirport('ZZZ'), isNull);
  });

  test('every listed airport zone exists in the timezone database', () {
    expect(airportZones.length, 309);
    for (final entry in airportZones.entries) {
      expect(entry.key, entry.key.toUpperCase());
      expect(entry.key.length, 3);
      expect(
        () => tz.getLocation(entry.value),
        returnsNormally,
        reason: '${entry.key} -> ${entry.value}',
      );
    }
  });

  test('hub codes resolve after normalization and unknown codes do not', () {
    expect(zoneForAirport('ICN'), 'Asia/Seoul');
    expect(zoneForAirport('ams'), 'Europe/Amsterdam');
    expect(zoneForAirport(' LAX '), 'America/Los_Angeles');
    expect(zoneForAirport('JFK'), 'America/New_York');
    expect(zoneForAirport('CDG'), 'Europe/Paris');
    expect(zoneForAirport('ZZZ'), isNull);
    expect(zoneForAirport(''), isNull);
  });
}
