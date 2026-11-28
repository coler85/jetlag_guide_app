enum GuideEventKind {
  arrival,
  light,
  meal,
  mealDeadline,
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
    this.inflightMissedNight = false,
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

  /// Inflight only: true when the window is the nearest cruise slice.
  final bool inflightMissedNight;

  bool get isSpan => endUtc != null;

  /// Planned wake for the alarm UI. Set only for planned sleep with an end.
  /// Recorded sleep never exposes a wake here.
  DateTime? get alarmWakeUtc =>
      kind == GuideEventKind.sleep ? endUtc : null;
}
