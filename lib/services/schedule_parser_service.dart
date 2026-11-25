import '../models/flight_schedule_input.dart';

enum ScheduleFileKind { image, pdf }

/// A file the crew picked. Bytes stay on disk until a real parser reads them.
class ScheduleFileRef {
  const ScheduleFileRef({required this.name, this.path, required this.kind});

  final String name;
  final String? path;
  final ScheduleFileKind kind;
}

/// Turns a roster export into [FlightScheduleInput].
///
/// Automatic recognition is not available yet. [parseFile] returns null so
/// the schedule tab can ask for the layover by hand. No sample layover is
/// invented here.
class ScheduleParserService {
  const ScheduleParserService();

  Future<FlightScheduleInput?> parseFile(ScheduleFileRef file) async {
    switch (file.kind) {
      case ScheduleFileKind.image:
      case ScheduleFileKind.pdf:
        return null;
    }
  }
}
