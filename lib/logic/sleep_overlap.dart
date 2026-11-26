import '../models/guide_event.dart';
import 'jetlag_clock.dart';

/// A planned sleep and the recorded sleeps that share any time with it.
///
/// The planned block stays intact. This only groups them for the timeline.
class SleepOverlap {
  const SleepOverlap({required this.plan, required this.logs});

  final GuideEvent plan;
  final List<GuideEvent> logs;
}

/// Pairs each planned sleep with the recorded sleeps that overlap it.
/// A record that misses every plan is left out, and so is a plan with no record.
List<SleepOverlap> pairOverlappingSleep(List<GuideEvent> events) {
  final logs = events
      .where(
        (event) =>
            event.kind == GuideEventKind.loggedSleep && event.endUtc != null,
      )
      .toList();
  final pairs = <SleepOverlap>[];
  for (final plan in events) {
    final planEnd = plan.endUtc;
    if (plan.kind != GuideEventKind.sleep || planEnd == null) continue;
    final hits = logs
        .where(
          (log) => _overlaps(plan.startUtc, planEnd, log.startUtc, log.endUtc!),
        )
        .toList();
    if (hits.isEmpty) continue;
    pairs.add(SleepOverlap(plan: plan, logs: hits));
  }
  return pairs;
}

Set<String> overlappedEventIds(List<SleepOverlap> pairs) {
  return {
    for (final pair in pairs) pair.plan.id,
    for (final pair in pairs) ...pair.logs.map((log) => log.id),
  };
}

bool _overlaps(DateTime a0, DateTime a1, DateTime b0, DateTime b1) {
  return a0.isBefore(b1) && b0.isBefore(a1);
}

String sleepPlanLine(DateTime startUtc, DateTime endUtc, String iana) {
  return '수면 계획 ${formatRange(startUtc, endUtc, iana)}';
}

String sleepLogLine(DateTime startUtc, DateTime endUtc, String iana) {
  return '기록 ${formatRange(startUtc, endUtc, iana)}';
}

/// How the recorded edges differ from the plan. States the clock difference only.
String sleepOverlapCaption({
  required DateTime planStart,
  required DateTime planEnd,
  required DateTime logStart,
  required DateTime logEnd,
}) {
  final fellAsleep = _edgePhrase(
    logStart.difference(planStart),
    early: '계획보다',
    late: '계획보다',
    earlyTail: '일찍 잠',
    lateTail: '늦게 잠',
    same: '계획과 같은 시각에 잠',
  );
  final woke = _edgePhrase(
    logEnd.difference(planEnd),
    early: '',
    late: '',
    earlyTail: '일찍 깸',
    lateTail: '늦게 깸',
    same: '같은 시각에 깸',
  );
  return '$fellAsleep, $woke';
}

String _edgePhrase(
  Duration delta, {
  required String early,
  required String late,
  required String earlyTail,
  required String lateTail,
  required String same,
}) {
  if (delta == Duration.zero) return same;
  final amount = _durationLabel(delta.abs());
  if (delta.isNegative) {
    return early.isEmpty ? '$amount $earlyTail' : '$early $amount $earlyTail';
  }
  return late.isEmpty ? '$amount $lateTail' : '$late $amount $lateTail';
}

String _durationLabel(Duration duration) {
  final minutes = duration.inMinutes;
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '$mins분';
  if (mins == 0) return '$hours시간';
  return '$hours시간 $mins분';
}
