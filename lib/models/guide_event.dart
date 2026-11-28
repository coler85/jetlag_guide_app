enum GuideEventKind {
  arrival,
  light,
  meal,
  caffeine,
  sleep,
  loggedSleep,
  pickup,
  showup,
  departure,
  inflight,
}

class GuideEvent {
  GuideEvent({
    required this.id,
    required this.kind,
    required DateTime startUtc,
    DateTime? endUtc,
    required this.title,
    required this.detail,
    this.missing = false,
  }) : startUtc = startUtc.toUtc(),
       endUtc = endUtc?.toUtc();

  final String id;
  final GuideEventKind kind;
  final DateTime startUtc;
  final DateTime? endUtc;
  final String title;
  final String detail;

  /// The instant was not injected. The row stays visible as a placeholder.
  final bool missing;

  bool get isSpan => endUtc != null;
}
