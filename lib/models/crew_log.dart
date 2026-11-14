enum CrewLogKind { caffeine, meal, sleep, wake }

extension CrewLogKindLabel on CrewLogKind {
  String get label {
    switch (this) {
      case CrewLogKind.caffeine:
        return '카페인';
      case CrewLogKind.meal:
        return '식사';
      case CrewLogKind.sleep:
        return '수면';
      case CrewLogKind.wake:
        return '기상';
    }
  }
}

class CrewLog {
  CrewLog({
    required this.id,
    required DateTime atUtc,
    required this.kind,
    required this.scheduleKey,
  }) : atUtc = atUtc.toUtc();

  final String id;
  final DateTime atUtc;
  final CrewLogKind kind;
  final String scheduleKey;

  Map<String, Object> toJson() => {
    'id': id,
    'at': atUtc.toUtc().toIso8601String(),
    'kind': kind.name,
    'schedule': scheduleKey,
  };

  static CrewLog? tryParse(Map<String, Object?> json) {
    final id = json['id'];
    final at = json['at'];
    final kindName = json['kind'];
    final schedule = json['schedule'];
    if (id is! String || at is! String || kindName is! String) return null;
    final atUtc = DateTime.tryParse(at);
    if (atUtc == null) return null;
    final kind = _kindFromName(kindName);
    if (kind == null) return null;
    return CrewLog(
      id: id,
      atUtc: atUtc.toUtc(),
      kind: kind,
      scheduleKey: schedule is String ? schedule : '',
    );
  }
}

CrewLogKind? _kindFromName(String name) {
  // Logs saved before the caffeine rename used this value.
  if (name == 'coffee') return CrewLogKind.caffeine;
  for (final kind in CrewLogKind.values) {
    if (kind.name == name) return kind;
  }
  return null;
}
