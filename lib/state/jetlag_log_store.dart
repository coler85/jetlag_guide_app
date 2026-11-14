import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/crew_log.dart';

/// Logs for this module only. The preference key does not overlap roster data.
class JetlagLogStore {
  const JetlagLogStore();

  static const preferenceKey = 'jetlag_guide_logs_v1';

  Future<List<CrewLog>> load(String scheduleKey) async {
    final all = await _read();
    final mine = all.where((log) => log.scheduleKey == scheduleKey).toList();
    mine.sort((a, b) => a.atUtc.compareTo(b.atUtc));
    return mine;
  }

  Future<void> save(String scheduleKey, List<CrewLog> logs) async {
    final all = await _read();
    final kept = all.where((log) => log.scheduleKey != scheduleKey);
    final prefs = await SharedPreferences.getInstance();
    final payload = [...kept, ...logs].map((log) => log.toJson()).toList();
    await prefs.setString(preferenceKey, jsonEncode(payload));
  }

  Future<List<CrewLog>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(preferenceKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final logs = <CrewLog>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final log = CrewLog.tryParse(Map<String, Object?>.from(item));
      if (log != null) logs.add(log);
    }
    return logs;
  }
}
