/// How the layover day is anchored. The crew can switch this at any time.
enum JetlagLifestyle {
  kstAnchor,
  hybrid,
  localAdapt;

  static const preferenceKey = 'jetlag_guide_lifestyle';

  static const bedMinute = 21 * 60;
  static const wakeMinute = 5 * 60;
  static const hybridCap = Duration(hours: 2);

  /// Anchor segment reads `$homeBaseTimezone 유지`. [homeBaseTimezone] is the
  /// saved IANA id, so the switcher tracks the home base instead of a fixed label.
  String switchLabel(String homeBaseTimezone) {
    switch (this) {
      case JetlagLifestyle.kstAnchor:
        final zone = homeBaseTimezone.trim();
        return '${zone.isEmpty ? '기준 시간대' : zone} 유지';
      case JetlagLifestyle.hybrid:
        return '하이브리드';
      case JetlagLifestyle.localAdapt:
        return '현지 적응';
    }
  }

  String sleepDetailFor(String homeBaseTimezone) {
    final home = homeBaseTimezone.trim().isEmpty
        ? '기준 시간대'
        : homeBaseTimezone.trim();
    switch (this) {
      case JetlagLifestyle.kstAnchor:
        return '$home 취침·기상을 유지합니다.';
      case JetlagLifestyle.hybrid:
        return '$home에서 현지 쪽으로 최대 2시간 옮깁니다.';
      case JetlagLifestyle.localAdapt:
        return '현지 낮과 밤에 맞춥니다.';
    }
  }

  static JetlagLifestyle fromName(String? raw) {
    for (final lifestyle in JetlagLifestyle.values) {
      if (lifestyle.name == raw) return lifestyle;
    }
    return JetlagLifestyle.kstAnchor;
  }
}
