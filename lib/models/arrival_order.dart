/// Order of the first meal and sleep after arrival when they sit close together.
enum ArrivalOrder {
  auto,
  restFirst,
  mealFirst;

  String get label {
    switch (this) {
      case ArrivalOrder.auto:
        return '자동';
      case ArrivalOrder.restFirst:
        return '먼저 휴식';
      case ArrivalOrder.mealFirst:
        return '먼저 식사';
    }
  }

  static ArrivalOrder fromName(String? raw) {
    for (final order in ArrivalOrder.values) {
      if (order.name == raw) return order;
    }
    return ArrivalOrder.auto;
  }
}
