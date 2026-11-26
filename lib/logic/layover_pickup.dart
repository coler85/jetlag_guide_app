// Minutes before the return departure. Positive when the pickup is earlier.
// The stepper moves by 10 minutes and stays inside 0 to 6 hours. A clock that
// is not on a 10-minute mark keeps its exact minute count.

const pickupLeadStepMinutes = 10;
const pickupLeadMaxMinutes = 6 * 60;

int pickupLeadMinutes(DateTime departureUtc, DateTime pickupUtc) {
  return departureUtc.toUtc().difference(pickupUtc.toUtc()).inMinutes;
}

DateTime pickupUtcFromLead(DateTime departureUtc, int leadMinutes) {
  return departureUtc.toUtc().subtract(Duration(minutes: leadMinutes));
}

/// Moves [minutes] by one step and keeps the result inside 0 to 6 hours.
int stepPickupLead(int minutes, int direction) {
  final delta = direction < 0 ? -pickupLeadStepMinutes : pickupLeadStepMinutes;
  final next = minutes + delta;
  if (next < 0) return 0;
  if (next > pickupLeadMaxMinutes) return pickupLeadMaxMinutes;
  return next;
}

/// `2시간 10분`, `2시간`, `7분`, or `0분`.
String pickupLeadSpan(int minutes) {
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '$mins분';
  if (mins == 0) return '$hours시간';
  return '$hours시간 $mins분';
}

/// `출발 2시간 10분 전`. A pickup after departure uses `후`.
String pickupRelativeToDeparture(int minutes) {
  if (minutes < 0) return '출발 ${pickupLeadSpan(-minutes)} 후';
  return '출발 ${pickupLeadSpan(minutes)} 전';
}
