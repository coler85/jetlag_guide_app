import 'jetlag_schedule.dart';

/// In-flight rest slot. Flight deck and cabin do not share a shift list.
enum BunkShift {
  p1LateRest,
  p2EarlyRest,
  cabinFirst,
  cabinSecond;

  JetlagCrewRole get role {
    switch (this) {
      case BunkShift.p1LateRest:
      case BunkShift.p2EarlyRest:
        return JetlagCrewRole.flightOps;
      case BunkShift.cabinFirst:
      case BunkShift.cabinSecond:
        return JetlagCrewRole.cabin;
    }
  }

  String get label {
    switch (this) {
      case BunkShift.p1LateRest:
        return 'P1 후반휴식';
      case BunkShift.p2EarlyRest:
        return 'P2 전반휴식';
      case BunkShift.cabinFirst:
        return '1교대';
      case BunkShift.cabinSecond:
        return '2교대';
    }
  }

  static List<BunkShift> forRole(JetlagCrewRole role) {
    switch (role) {
      case JetlagCrewRole.flightOps:
        return const [BunkShift.p1LateRest, BunkShift.p2EarlyRest];
      case JetlagCrewRole.cabin:
        return const [BunkShift.cabinFirst, BunkShift.cabinSecond];
    }
  }
}

enum BunkCueKind { caffeine, sleep, wake }

class BunkCue {
  const BunkCue({
    required this.kind,
    required this.title,
    required this.window,
    required this.supporting,
    required this.detail,
  });

  final BunkCueKind kind;
  final String title;

  /// Local wall time, the primary line.
  final String window;

  /// Home base and UTC, drawn under [window].
  final String supporting;
  final String detail;
}
