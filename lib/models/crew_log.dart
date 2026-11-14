enum CrewLogKind { coffee, meal, sleep, wake }

extension CrewLogKindLabel on CrewLogKind {
  String get label {
    switch (this) {
      case CrewLogKind.coffee:
        return '커피';
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
  const CrewLog({
    required this.id,
    required this.atUtc,
    required this.kind,
    required this.scheduleKey,
  });

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
    for (final kind in CrewLogKind.values) {
      if (kind.name == kindName) {
        return CrewLog(
          id: id,
          atUtc: atUtc.toUtc(),
          kind: kind,
          scheduleKey: schedule is String ? schedule : '',
        );
      }
    }
    return null;
  }
}
