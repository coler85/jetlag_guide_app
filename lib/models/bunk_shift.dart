import 'jetlag_schedule.dart';

/// In-flight rest slot. Flight deck and cabin do not share a shift list.
enum BunkShift {
  p2First,
  p1Second,
  cabinFirst,
  cabinSecond;

  JetlagCrewRole get role {
    switch (this) {
      case BunkShift.p2First:
      case BunkShift.p1Second:
        return JetlagCrewRole.flightOps;
      case BunkShift.cabinFirst:
      case BunkShift.cabinSecond:
        return JetlagCrewRole.cabin;
    }
  }

  String get label {
    switch (this) {
      case BunkShift.p2First:
        return 'P2 전반';
      case BunkShift.p1Second:
        return 'P1 후반';
      case BunkShift.cabinFirst:
        return '1교대';
      case BunkShift.cabinSecond:
        return '2교대';
    }
  }

  static List<BunkShift> forRole(JetlagCrewRole role) {
    switch (role) {
      case JetlagCrewRole.flightOps:
        return const [BunkShift.p2First, BunkShift.p1Second];
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
    required this.detail,
  });

  final BunkCueKind kind;
  final String title;
  final String window;
  final String detail;
}
