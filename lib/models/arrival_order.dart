/// Order of the first meal and sleep after arrival when they sit close together.
enum ArrivalOrder {
  restFirst,
  mealFirst;

  String get label {
    switch (this) {
      case ArrivalOrder.restFirst:
        return '휴식 먼저';
      case ArrivalOrder.mealFirst:
        return '식사 먼저';
    }
  }

  /// Loads a stored name. Only `mealFirst` maps to meal-first; `auto`,
  /// `restFirst`, null, and anything else become rest-first.
  static ArrivalOrder fromName(String? raw) {
    if (raw == ArrivalOrder.mealFirst.name) return ArrivalOrder.mealFirst;
    return ArrivalOrder.restFirst;
  }
}
