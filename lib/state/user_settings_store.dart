import 'package:shared_preferences/shared_preferences.dart';

import '../models/arrival_order.dart';
import '../models/user_settings.dart';

/// Personal routine for this module. Keys do not overlap roster data.
class UserSettingsStore {
  const UserSettingsStore();

  static const bedKey = 'jetlag_guide_default_bed_minute';
  static const wakeKey = 'jetlag_guide_default_wake_minute';
  static const prepKey = 'jetlag_guide_prep_minutes';
  static const commuteKey = 'jetlag_guide_commute_minutes';
  static const arrivalToSleepKey = 'jetlag_guide_arrival_to_sleep_minutes';
  static const arrivalDeboardKey = 'jetlag_guide_arrival_deboard_minutes';
  static const hotelTransferKey = 'jetlag_guide_hotel_transfer_minutes';
  static const afterHotelReadyKey = 'jetlag_guide_after_hotel_ready_minutes';
  static const arrivalOrderKey = 'jetlag_guide_arrival_order';
  static const hybridKey = 'jetlag_guide_hybrid_max_shift_hours';
  static const homeShowupLeadKey = 'jetlag_guide_home_showup_lead_minutes';
  static const sleepTargetKey = 'jetlag_guide_sleep_target_minutes';

  Future<UserSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = UserSettings.defaults;
    final parts = _loadArrivalParts(prefs, defaults);
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
      arrivalDeboard: parts.deboard,
      hotelTransfer: parts.transfer,
      afterHotelReady: parts.ready,
      arrivalOrder: ArrivalOrder.fromName(prefs.getString(arrivalOrderKey)),
      hybridMaxShiftHours:
          prefs.getInt(hybridKey) ?? defaults.hybridMaxShiftHours,
      homeShowupLead: Duration(
        minutes:
            prefs.getInt(homeShowupLeadKey) ??
            defaults.homeShowupLead.inMinutes,
      ),
      chosenSleep: Duration(
        minutes: prefs.getInt(sleepTargetKey) ?? defaults.chosenSleep.inMinutes,
      ),
    ).normalized();
  }

  Future<void> save(UserSettings settings) async {
    final stored = settings.normalized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(bedKey, stored.defaultBedTime.minuteOfDay);
    await prefs.setInt(wakeKey, stored.defaultWakeTime.minuteOfDay);
    await prefs.setInt(prepKey, stored.prepTime.inMinutes);
    await prefs.setInt(commuteKey, stored.commuteTime.inMinutes);
    await prefs.setInt(arrivalDeboardKey, stored.arrivalDeboard.inMinutes);
    await prefs.setInt(hotelTransferKey, stored.hotelTransfer.inMinutes);
    await prefs.setInt(afterHotelReadyKey, stored.afterHotelReady.inMinutes);
    await prefs.setInt(arrivalToSleepKey, stored.arrivalToSleep.inMinutes);
    await prefs.setString(arrivalOrderKey, stored.arrivalOrder.name);
    await prefs.setInt(hybridKey, stored.hybridMaxShiftHours);
    await prefs.setInt(homeShowupLeadKey, stored.homeShowupLead.inMinutes);
    await prefs.setInt(sleepTargetKey, stored.sleepTarget.inMinutes);
  }

  /// When the three part keys are missing, split the legacy total 1:2:2.
  ({Duration deboard, Duration transfer, Duration ready}) _loadArrivalParts(
    SharedPreferences prefs,
    UserSettings defaults,
  ) {
    final hasParts =
        prefs.containsKey(arrivalDeboardKey) &&
        prefs.containsKey(hotelTransferKey) &&
        prefs.containsKey(afterHotelReadyKey);
    if (hasParts) {
      return (
        deboard: Duration(
          minutes:
              prefs.getInt(arrivalDeboardKey) ??
              defaults.arrivalDeboard.inMinutes,
        ),
        transfer: Duration(
          minutes:
              prefs.getInt(hotelTransferKey) ??
              defaults.hotelTransfer.inMinutes,
        ),
        ready: Duration(
          minutes:
              prefs.getInt(afterHotelReadyKey) ??
              defaults.afterHotelReady.inMinutes,
        ),
      );
    }
    final totalMinutes =
        prefs.getInt(arrivalToSleepKey) ?? defaults.arrivalToSleep.inMinutes;
    return UserSettings.splitArrivalToSleep(Duration(minutes: totalMinutes));
  }

  DayTime _dayTime(int? minuteOfDay, DayTime fallback) {
    if (minuteOfDay == null) return fallback;
    return DayTime(hour: 0, minute: minuteOfDay).normalized();
  }
}
