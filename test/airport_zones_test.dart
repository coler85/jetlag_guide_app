import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/data/airport_zones.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(ensureJetlagTimeZones);

  test('every listed airport zone exists in the timezone database', () {
    expect(airportZones.length, greaterThanOrEqualTo(150));
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
