import 'package:timezone/timezone.dart' as tz;

import 'jetlag_clock.dart';

/// Last-resort IANA id when nothing valid is stored or selected.
const kJetlagFallbackHomeBase = 'Asia/Seoul';

/// Major bases the records tab offers. Ids are IANA, not fixed offsets.
const kHomeBaseZones = <HomeBaseZone>[
  HomeBaseZone(id: 'Asia/Seoul', city: '서울'),
  HomeBaseZone(id: 'Asia/Tokyo', city: '도쿄'),
  HomeBaseZone(id: 'Asia/Shanghai', city: '상하이'),
  HomeBaseZone(id: 'Asia/Hong_Kong', city: '홍콩'),
  HomeBaseZone(id: 'Asia/Singapore', city: '싱가포르'),
  HomeBaseZone(id: 'Asia/Bangkok', city: '방콕'),
  HomeBaseZone(id: 'Asia/Dubai', city: '두바이'),
  HomeBaseZone(id: 'Asia/Kolkata', city: '콜카타'),
  HomeBaseZone(id: 'Europe/London', city: '런던'),
  HomeBaseZone(id: 'Europe/Paris', city: '파리'),
  HomeBaseZone(id: 'Europe/Berlin', city: '베를린'),
  HomeBaseZone(id: 'Europe/Rome', city: '로마'),
  HomeBaseZone(id: 'America/New_York', city: '뉴욕'),
  HomeBaseZone(id: 'America/Chicago', city: '시카고'),
  HomeBaseZone(id: 'America/Denver', city: '덴버'),
  HomeBaseZone(id: 'America/Los_Angeles', city: '로스앤젤레스'),
  HomeBaseZone(id: 'America/Sao_Paulo', city: '상파울루'),
  HomeBaseZone(id: 'Australia/Sydney', city: '시드니'),
  HomeBaseZone(id: 'Pacific/Auckland', city: '오클랜드'),
  HomeBaseZone(id: 'Etc/UTC', city: 'UTC'),
];

class HomeBaseZone {
  const HomeBaseZone({required this.id, required this.city});

  final String id;
  final String city;

  String get menuLabel => '$city · $id';
}

/// Zones for the picker, including a saved id that is not in the catalog.
List<HomeBaseZone> homeBaseZoneChoices(String selected) {
  final trimmed = selected.trim();
  final known = [for (final zone in kHomeBaseZones) zone.id];
  if (trimmed.isEmpty || known.contains(trimmed)) return kHomeBaseZones;
  return [HomeBaseZone(id: trimmed, city: trimmed), ...kHomeBaseZones];
}

/// Returns [raw] when it is a real IANA zone. Otherwise the Seoul fallback.
///
/// Empty, unknown, and a missing timezone database all land on the fallback
/// so timeline math never receives a zone [tz.getLocation] would reject.
String resolveHomeBaseTimezone(String? raw) {
  try {
    ensureJetlagTimeZones();
  } catch (_) {
    return kJetlagFallbackHomeBase;
  }
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return kJetlagFallbackHomeBase;
  try {
    tz.getLocation(value);
    return value;
  } catch (_) {
    return kJetlagFallbackHomeBase;
  }
}
