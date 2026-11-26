import '../models/sleep_log.dart';
import 'home_departure.dart';

/// Signed sleep balance. Negative means the crew is short of the usual night.
class SleepDebtSnapshot {
  const SleepDebtSnapshot(this.balance, {this.recorded = true});

  final Duration balance;

  /// False until the crew has saved at least one sleep interval.
  final bool recorded;

  bool get inDebt => recorded && balance.isNegative;

  String get label => recorded ? formatSleepBalance(balance) : '수면 기록 없음';
}

class SleepDebtCalculator {
  const SleepDebtCalculator();

  /// Each logged night contributes actual minus usual.
  /// With no saved night the balance stays zero. A dawn report that has not
  /// been logged yet subtracts its shortfall only after the first night is in.
  /// A log that overlaps that recommended window replaces the estimate.
  SleepDebtSnapshot evaluate({
    required Duration usual,
    required List<SleepLog> logs,
    HomeDeparturePlan departure = HomeDeparturePlan.none,
  }) {
    var balance = Duration.zero;
    var coversPlan = false;
    var recorded = false;
    final planStart = departure.recommendedStartUtc;
    final planEnd = departure.recommendedEndUtc;
    for (final log in logs) {
      if (!log.isValid) continue;
      recorded = true;
      balance += log.duration - usual;
      if (departure.applies &&
          planStart != null &&
          planEnd != null &&
          log.overlaps(planStart, planEnd)) {
        coversPlan = true;
      }
    }
    if (!recorded) {
      return const SleepDebtSnapshot(Duration.zero, recorded: false);
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
