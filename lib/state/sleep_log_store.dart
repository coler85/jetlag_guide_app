import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sleep_log.dart';

/// Completed sleep intervals for this module only.
class SleepLogStore {
  const SleepLogStore();

  static const preferenceKey = 'jetlag_guide_sleep_logs_v1';

  Future<List<SleepLog>> load(String scheduleKey) async {
    final all = await _read();
    final mine = all.where((log) => log.scheduleKey == scheduleKey).toList();
    mine.sort((a, b) => a.startUtc.compareTo(b.startUtc));
    return mine;
  }

  Future<void> save(String scheduleKey, List<SleepLog> logs) async {
    final all = await _read();
    final kept = all.where((log) => log.scheduleKey != scheduleKey);
    final prefs = await SharedPreferences.getInstance();
    final payload = [...kept, ...logs].map((log) => log.toJson()).toList();
    await prefs.setString(preferenceKey, jsonEncode(payload));
  }

  Future<List<SleepLog>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(preferenceKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final logs = <SleepLog>[];
    final used = <String>{};
    for (final item in decoded) {
      if (item is! Map) continue;
      final parsed = SleepLog.tryParse(Map<String, Object?>.from(item));
      if (parsed == null) continue;
      final id = _uniqueId(parsed.id, used);
      used.add(id);
      logs.add(
        id == parsed.id
            ? parsed
            : SleepLog(
                id: id,
                startUtc: parsed.startUtc,
                endUtc: parsed.endUtc,
                scheduleKey: parsed.scheduleKey,
              ),
      );
    }
    return logs;
  }

  /// A second copy of the same legacy interval gets its own id.
  static String _uniqueId(String base, Set<String> used) {
    if (!used.contains(base)) return base;
    var n = 2;
    while (used.contains('$base#$n')) {
      n++;
    }
    return '$base#$n';
  }
}
