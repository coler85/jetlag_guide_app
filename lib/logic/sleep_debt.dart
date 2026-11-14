import '../models/sleep_log.dart';
import 'home_departure.dart';

/// Signed sleep balance. Negative means the crew is short of the usual night.
class SleepDebtSnapshot {
  const SleepDebtSnapshot(this.balance);

  final Duration balance;

  bool get inDebt => balance.isNegative;

  String get label => formatSleepBalance(balance);
}

class SleepDebtCalculator {
  const SleepDebtCalculator();

  /// Each logged night contributes actual minus usual.
  /// A dawn report that has not been logged yet also subtracts its shortfall,
  /// so the debt starts before the crew types the night in. A log that
  /// overlaps that recommended window replaces the estimate.
  SleepDebtSnapshot evaluate({
    required Duration usual,
    required List<SleepLog> logs,
    HomeDeparturePlan departure = HomeDeparturePlan.none,
  }) {
    var balance = Duration.zero;
    var coversPlan = false;
    final planStart = departure.recommendedStartUtc;
    final planEnd = departure.recommendedEndUtc;
    for (final log in logs) {
      if (!log.isValid) continue;
      balance += log.duration - usual;
      if (departure.applies &&
          planStart != null &&
          planEnd != null &&
          log.overlaps(planStart, planEnd)) {
        coversPlan = true;
      }
    }
    if (departure.applies &&
        !coversPlan &&
        departure.shortfall > Duration.zero) {
      balance -= departure.shortfall;
    }
    return SleepDebtSnapshot(balance);
  }
}

/// `-2시간 30분` when short, `+1시간` when ahead, `0분` when even.
String formatSleepBalance(Duration balance) {
  final negative = balance.isNegative;
  final minutes = balance.abs().inMinutes;
  if (minutes == 0) return '0분';
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  final parts = <String>[if (hours > 0) '$hours시간', if (mins > 0) '$mins분'];
  final body = parts.join(' ');
  return negative ? '-$body' : '+$body';
}
