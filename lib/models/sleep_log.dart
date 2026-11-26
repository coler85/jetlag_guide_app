/// A completed sleep the crew entered themselves.
///
/// Both edges are absolute instants. Wall-clock editing happens in the sheet
/// and is converted to UTC before this object is stored.
class SleepLog {
  SleepLog({
    required this.id,
    required DateTime startUtc,
    required DateTime endUtc,
    required this.scheduleKey,
  }) : startUtc = startUtc.toUtc(),
       endUtc = endUtc.toUtc();

  final String id;
  final DateTime startUtc;
  final DateTime endUtc;
  final String scheduleKey;

  static const eventIdPrefix = 'logged-sleep-';

  static String eventIdFor(String id) => '$eventIdPrefix$id';

  /// Log id stored on a timeline block, or null when the block is not a log.
  static String? idFromEvent(String eventId) {
    if (!eventId.startsWith(eventIdPrefix)) return null;
    final id = eventId.substring(eventIdPrefix.length);
    return id.isEmpty ? null : id;
  }

  /// Stable id for a save that predates [id]. The same interval reads back
  /// as the same id, so an older file is not dropped.
  static String legacyId({
    required DateTime startUtc,
    required DateTime endUtc,
    required String scheduleKey,
  }) {
    final start = startUtc.toUtc().microsecondsSinceEpoch;
    final end = endUtc.toUtc().microsecondsSinceEpoch;
    return 'legacy-$start-$end-$scheduleKey';
  }

  Duration get duration => endUtc.difference(startUtc);

  bool get isValid => endUtc.isAfter(startUtc);

  bool covers(DateTime instant) {
    final utc = instant.toUtc();
    return !startUtc.isAfter(utc) && endUtc.isAfter(utc);
  }

  bool overlaps(DateTime start, DateTime end) {
    return startUtc.isBefore(end.toUtc()) && start.toUtc().isBefore(endUtc);
  }

  Map<String, Object> toJson() => {
    'id': id,
    'start': startUtc.toUtc().toIso8601String(),
    'end': endUtc.toUtc().toIso8601String(),
    'schedule': scheduleKey,
  };

  static SleepLog? tryParse(Map<String, Object?> json) {
    final start = json['start'];
    final end = json['end'];
    final schedule = json['schedule'];
    if (start is! String || end is! String) return null;
    final startUtc = DateTime.tryParse(start);
    final endUtc = DateTime.tryParse(end);
    if (startUtc == null || endUtc == null) return null;
    if (!endUtc.toUtc().isAfter(startUtc.toUtc())) return null;
    final scheduleKey = schedule is String ? schedule : '';
    final rawId = json['id'];
    final id = rawId is String && rawId.trim().isNotEmpty
        ? rawId.trim()
        : legacyId(
            startUtc: startUtc,
            endUtc: endUtc,
            scheduleKey: scheduleKey,
          );
    return SleepLog(
      id: id,
      startUtc: startUtc,
      endUtc: endUtc,
      scheduleKey: scheduleKey,
    );
  }
}
