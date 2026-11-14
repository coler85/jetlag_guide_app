/// Caps how far Hybrid mode slides home-base anchors toward local time.
///
/// The shift is the short arc between the two clocks. When that arc is inside
/// [maxShift], the anchors move the whole way (the same amount a full local
/// adaptation would move them). When the arc is larger, the move stops at
/// the cap instead of chasing local time.
class HybridStrategy {
  const HybridStrategy();

  Duration shift({required Duration zoneOffset, required Duration maxShift}) {
    var minutes = -zoneOffset.inMinutes;
    const day = 24 * 60;
    const half = 12 * 60;
    while (minutes > half) {
      minutes -= day;
    }
    while (minutes <= -half) {
      minutes += day;
    }
    final cap = maxShift.inMinutes.abs();
    if (minutes > cap) minutes = cap;
    if (minutes < -cap) minutes = -cap;
    return Duration(minutes: minutes);
  }
}
