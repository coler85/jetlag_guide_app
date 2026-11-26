import '../models/sleep_log.dart';

/// Signed sleep balance. Negative means saved sleep is short of the target.
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

  /// Adds only the shortfall of each saved log against [target].
  /// A log at or above [target] adds nothing, and extra hours do not cancel
  /// another log. With no saved log the balance stays zero: an estimated
  /// dawn shortfall is not part of this number.
  SleepDebtSnapshot evaluate({
    required Duration target,
    required List<SleepLog> logs,
  }) {
    var shortfall = Duration.zero;
    var recorded = false;
    for (final log in logs) {
      if (!log.isValid) continue;
      recorded = true;
      final missing = target - log.duration;
      if (missing > Duration.zero) shortfall += missing;
    }
    if (!recorded) {
      return const SleepDebtSnapshot(Duration.zero, recorded: false);
    }
    return SleepDebtSnapshot(-shortfall);
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
