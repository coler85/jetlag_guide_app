import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_settings.dart';

/// Personal routine for this module. Keys do not overlap roster data.
class UserSettingsStore {
  const UserSettingsStore();

  static const bedKey = 'jetlag_guide_default_bed_minute';
  static const wakeKey = 'jetlag_guide_default_wake_minute';
  static const prepKey = 'jetlag_guide_prep_minutes';
  static const commuteKey = 'jetlag_guide_commute_minutes';
  static const hybridKey = 'jetlag_guide_hybrid_max_shift_hours';

  Future<UserSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = UserSettings.defaults;
    return UserSettings(
      defaultBedTime: _dayTime(prefs.getInt(bedKey), defaults.defaultBedTime),
      defaultWakeTime: _dayTime(
        prefs.getInt(wakeKey),
        defaults.defaultWakeTime,
      ),
      prepTime: Duration(
        minutes: prefs.getInt(prepKey) ?? defaults.prepTime.inMinutes,
      ),
      commuteTime: Duration(
        minutes: prefs.getInt(commuteKey) ?? defaults.commuteTime.inMinutes,
      ),
      hybridMaxShiftHours:
          prefs.getInt(hybridKey) ?? defaults.hybridMaxShiftHours,
    ).normalized();
  }

  Future<void> save(UserSettings settings) async {
    final stored = settings.normalized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(bedKey, stored.defaultBedTime.minuteOfDay);
    await prefs.setInt(wakeKey, stored.defaultWakeTime.minuteOfDay);
    await prefs.setInt(prepKey, stored.prepTime.inMinutes);
    await prefs.setInt(commuteKey, stored.commuteTime.inMinutes);
    await prefs.setInt(hybridKey, stored.hybridMaxShiftHours);
  }

  DayTime _dayTime(int? minuteOfDay, DayTime fallback) {
    if (minuteOfDay == null) return fallback;
    return DayTime(hour: 0, minute: minuteOfDay).normalized();
  }
}
