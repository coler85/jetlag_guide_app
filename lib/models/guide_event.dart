enum GuideEventKind {
  arrival,
  light,
  meal,
  caffeine,
  sleep,
  pickup,
  showup,
  departure,
}

class GuideEvent {
  const GuideEvent({
    required this.id,
    required this.kind,
    required this.startUtc,
    this.endUtc,
    required this.title,
    required this.detail,
    this.missing = false,
  });

  final String id;
  final GuideEventKind kind;
  final DateTime startUtc;
  final DateTime? endUtc;
  final String title;
  final String detail;

  /// Pickup was not injected. The row stays visible so the bunk card can sit
  /// under it.
  final bool missing;

  bool get isSpan => endUtc != null;
}
