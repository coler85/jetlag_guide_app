import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/flight_schedule_input.dart';

/// The layover the crew adopted. Sample previews are not written here.
class FlightScheduleStore {
  const FlightScheduleStore();

  static const preferenceKey = 'jetlag_guide_schedule_v1';

  Future<FlightScheduleInput?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(preferenceKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return FlightScheduleInput.tryParse(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> save(FlightScheduleInput input) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preferenceKey, jsonEncode(input.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(preferenceKey);
  }
}
