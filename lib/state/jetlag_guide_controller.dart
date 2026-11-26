import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/jetlag_calculator.dart';
import '../models/bunk_shift.dart';
import '../models/crew_log.dart';
import '../models/flight_schedule_input.dart';
import '../models/jetlag_schedule.dart';
import '../models/lifestyle.dart';
import '../models/sleep_log.dart';
import '../models/user_settings.dart';
import '../notifications/jetlag_alert_channel.dart';
import '../notifications/jetlag_alert_scheduler.dart';
import 'flight_schedule_store.dart';
import 'jetlag_log_store.dart';
import 'jetlag_state.dart';
import 'sleep_log_store.dart';
import 'user_settings_store.dart';

class JetlagGuideController extends ChangeNotifier {
  JetlagGuideController({
    JetlagScheduleSnapshot? schedule,
    required this.logStore,
    required this.alerts,
    DateTime Function()? now,
    JetLagState? homeBase,
    JetLagCalculator? calculator,
    UserSettingsStore? settingsStore,
    SleepLogStore? sleepLogStore,
    FlightScheduleStore? scheduleStore,
  }) : _schedule = schedule,
       _now = now ?? _readUtcNow,
       role = schedule?.crewRole ?? JetlagCrewRole.flightOps,
       _home = homeBase ?? JetLagState(),
       _calculator = calculator ?? const JetLagCalculator(),
       _settingsStore = settingsStore ?? const UserSettingsStore(),
       _sleepLogStore = sleepLogStore ?? const SleepLogStore(),
       _scheduleStore = scheduleStore ?? const FlightScheduleStore() {
    if (_schedule != null) _timeline = _safeTimeline();
    _home.addListener(_onHomeBaseChanged);
  }

  final JetlagLogStore logStore;
  final JetlagAlertScheduler alerts;
  final DateTime Function() _now;

  /// Device clock as an absolute UTC instant. Wall-clock fields are display-only.
  static DateTime _readUtcNow() => DateTime.now().toUtc();
  final JetLagState _home;
  final JetLagCalculator _calculator;
  final UserSettingsStore _settingsStore;
  final SleepLogStore _sleepLogStore;
  final FlightScheduleStore _scheduleStore;

  JetlagScheduleSnapshot? _schedule;
  bool _sampleSchedule = false;
  int _revision = 0;
  JetlagCrewRole role;
  JetlagLifestyle lifestyle = JetlagLifestyle.kstAnchor;
  UserSettings settings = UserSettings.defaults;
  BunkShift? bunkShift;

  /// The journey last adopted or loaded. Null when the guide has no schedule.
  FlightScheduleInput? journey;
  List<CrewLog> logs = const [];
  List<SleepLog> sleepLogs = const [];
  bool alertsEnabled = false;
  int _lifestyleEpoch = 0;
  int _settingsEpoch = 0;
  bool _ready = false;
  bool _disposed = false;

  JetLagTimeline? _timeline;

  bool get hasSchedule => _schedule != null;

  /// True while the timeline is showing the unsaved sample layover.
  bool get isSampleSchedule => _sampleSchedule && hasSchedule;

  Future<void> _tail = Future<void>.value();
  int _serial = 0;

  /// Layover facts with the saved home base applied.
  JetlagScheduleSnapshot get schedule => timeline.schedule;

  JetLagTimeline get timeline {
    final built = _timeline;
    if (built == null) {
      throw StateError('Jet Lag Guide has no flight schedule');
    }
    return built;
  }

  /// Replaces the layover and reloads logs for that key.
  ///
  /// A real layover is written to preferences as UTC JSON. A [sample] preview
  /// stays in memory only, so the next launch still opens the guide.
  Future<void> adoptSchedule(FlightScheduleInput input, {bool sample = false}) {
    final revision = ++_revision;
    final snapshot = input.toSnapshot();
    _schedule = snapshot;
    _sampleSchedule = sample;
    journey = input;
    role = snapshot.crewRole;
    bunkShift = _savedBunk(input, snapshot.crewRole);
    logs = const [];
    sleepLogs = const [];
    _publish();
    return _lock(() async {
      if (!_current(revision)) return;
      if (!sample) await _scheduleStore.save(input);
      if (!_current(revision)) return;
      final current = _schedule;
      if (current == null || current.key != snapshot.key) return;
      final loadedLogs = await logStore.load(snapshot.key);
      final loadedSleep = await _sleepLogStore.load(snapshot.key);
      if (!_current(revision) || _schedule?.key != snapshot.key) return;
      logs = loadedLogs;
      sleepLogs = loadedSleep;
      _publish();
      if (!_current(revision) || !alertsEnabled) return;
      await _syncPickupAlert();
    });
  }

  /// Drops the in-memory layover and the saved copy.
  Future<void> clearSchedule() {
    final revision = ++_revision;
    _schedule = null;
    _timeline = null;
    _sampleSchedule = false;
    journey = null;
    bunkShift = null;
    logs = const [];
    sleepLogs = const [];
    _publish();
    return _lock(() async {
      await _scheduleStore.clear();
      if (!_current(revision) || !alertsEnabled) return;
      try {
        await alerts.cancel(id: JetlagAlertChannel.pickupNotificationId);
      } catch (error, stack) {
        debugPrint('jetlag clear alert failed: $error\n$stack');
      }
    });
  }

  String get homeBaseTimezone => _home.homeBaseTimezone;

  bool get homeBaseRecovered => _home.recovered;

  /// False until preferences, including the home base, have been read.
  bool get isReady => _ready;

  DateTime now() => _now().toUtc();

  Future<void> load() {
    return _lock(() async {
      final revision = _revision;
      try {
        final epoch = _lifestyleEpoch;
        final settingsEpoch = _settingsEpoch;
        await _home.load();
        final loadedSettings = await _settingsStore.load();
        if (settingsEpoch == _settingsEpoch && !_disposed) {
          settings = loadedSettings;
        }
        if (_current(revision) && _schedule == null) {
          final saved = await _scheduleStore.load();
          if (_current(revision) && _schedule == null && saved != null) {
            journey = saved;
            _schedule = saved.toSnapshot();
            role = saved.crewRole;
            bunkShift = _savedBunk(saved, saved.crewRole);
            _sampleSchedule = false;
          }
        }
        final schedule = _current(revision) ? _schedule : null;
        if (schedule != null) {
          final key = schedule.key;
          final loadedLogs = await logStore.load(key);
          final loadedSleep = await _sleepLogStore.load(key);
          if (_current(revision) && _schedule?.key == key) {
            logs = loadedLogs;
            sleepLogs = loadedSleep;
          }
        }
        final prefs = await SharedPreferences.getInstance();
        if (!_disposed) {
          alertsEnabled = prefs.getBool(JetlagAlertChannel.enabledKey) ?? false;
          if (epoch == _lifestyleEpoch) {
            lifestyle = JetlagLifestyle.fromName(
              prefs.getString(JetlagLifestyle.preferenceKey),
            );
          }
        }
      } catch (error, stack) {
        debugPrint('jetlag guide load failed: $error\n$stack');
      } finally {
        if (!_disposed) {
          _ready = true;
          _publish();
        }
      }
      if (_disposed || !alertsEnabled || _schedule == null) return;
      if (!_current(revision)) return;
      final ready = await alerts.ensureChannel();
      if (ready && _current(revision)) await _syncPickupAlert();
    });
  }

  void setHomeBaseTimezone(String iana) {
    unawaited(_home.setHomeBaseTimezone(iana));
  }

  void setUserSettings(UserSettings next) {
    final normalized = next.normalized();
    if (normalized == settings) return;
    settings = normalized;
    final epoch = ++_settingsEpoch;
    _publish();
    unawaited(
      _lock(() async {
        if (epoch != _settingsEpoch || _disposed) return;
        await _settingsStore.save(settings);
      }),
    );
  }

  Future<void> addSleepLog({
    required DateTime startUtc,
    required DateTime endUtc,
  }) {
    return _lock(() async {
      final schedule = _schedule;
      if (_disposed || schedule == null) return;
      final start = startUtc.toUtc();
      final end = endUtc.toUtc();
      if (!end.isAfter(start)) return;
      final entry = SleepLog(
        id: 'sleep-${now().microsecondsSinceEpoch}-${_serial++}',
        startUtc: start,
        endUtc: end,
        scheduleKey: schedule.key,
      );
      final next = [...sleepLogs, entry];
      await _sleepLogStore.save(schedule.key, next);
      if (_disposed) return;
      sleepLogs = next;
      _publish();
    });
  }

  Future<void> updateSleepLog({
    required String id,
    required DateTime startUtc,
    required DateTime endUtc,
  }) {
    return _lock(() async {
      final schedule = _schedule;
      if (_disposed || schedule == null) return;
      final start = startUtc.toUtc();
      final end = endUtc.toUtc();
      if (!end.isAfter(start)) return;
      final index = sleepLogs.indexWhere((log) => log.id == id);
      if (index < 0) return;
      final current = sleepLogs[index];
      final next = [...sleepLogs];
      next[index] = SleepLog(
        id: current.id,
        startUtc: start,
        endUtc: end,
        scheduleKey: current.scheduleKey,
      );
      await _sleepLogStore.save(schedule.key, next);
      if (_disposed) return;
      sleepLogs = next;
      _publish();
    });
  }

  Future<void> removeSleepLog(String id) {
    return _lock(() async {
      final schedule = _schedule;
      if (_disposed || schedule == null) return;
      final next = sleepLogs.where((log) => log.id != id).toList();
      await _sleepLogStore.save(schedule.key, next);
      if (_disposed) return;
      sleepLogs = next;
      _publish();
    });
  }

  Future<void> addLog(CrewLogKind kind) {
    return _lock(() async {
      final schedule = _schedule;
      if (schedule == null) return;
      final entry = CrewLog(
        id: '${now().microsecondsSinceEpoch}-${_serial++}',
        atUtc: now(),
        kind: kind,
        scheduleKey: schedule.key,
      );
      final next = [...logs, entry];
      await logStore.save(schedule.key, next);
      logs = next;
      _publish();
    });
  }

  Future<void> removeLog(String id) {
    return _lock(() async {
      final schedule = _schedule;
      if (schedule == null) return;
      final next = logs.where((log) => log.id != id).toList();
      await logStore.save(schedule.key, next);
      logs = next;
      _publish();
    });
  }

  void setLifestyle(JetlagLifestyle next) {
    if (lifestyle == next) return;
    lifestyle = next;
    final epoch = ++_lifestyleEpoch;
    _publish();
    unawaited(
      _lock(() async {
        if (epoch != _lifestyleEpoch) return;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(JetlagLifestyle.preferenceKey, next.name);
      }),
    );
  }

  BunkShift? _savedBunk(FlightScheduleInput input, JetlagCrewRole crew) {
    final candidate = input.returnBunk ?? input.outboundBunk;
    if (candidate != null && candidate.role == crew) return candidate;
    return null;
  }

  void selectBunk(BunkShift shift) {
    if (shift.role != role) return;
    bunkShift = shift;
    _publish();
  }

  void setRole(JetlagCrewRole next) {
    role = next;
    if (bunkShift != null && bunkShift!.role != next) bunkShift = null;
    _publish();
  }

  Future<void> setPickup(DateTime pickupUtc) {
    final revision = _revision;
    return _lock(() async {
      final schedule = _schedule;
      if (schedule == null || !_current(revision)) return;
      final saved = (journey ?? FlightScheduleInput.fromSnapshot(schedule))
          .withLayoverPickup(pickupUtc.toUtc());
      journey = saved;
      _schedule = saved.toSnapshot();
      _publish();
      if (!_sampleSchedule && _current(revision)) {
        await _scheduleStore.save(saved);
      }
      if (!_current(revision) || !alertsEnabled) return;
      await _syncPickupAlert();
    });
  }

  /// Returns false when the dedicated channel could not be armed.
  Future<bool> setAlertsEnabled(bool enabled) {
    return _lock(() async {
      if (!enabled) {
        alertsEnabled = false;
        await _writeEnabled(false);
        await alerts.cancel(id: JetlagAlertChannel.pickupNotificationId);
        _publish();
        return true;
      }
      final allowed = await alerts.requestPermission();
      final ready = allowed && await alerts.ensureChannel();
      if (!ready) {
        alertsEnabled = false;
        await _writeEnabled(false);
        _publish();
        return false;
      }
      alertsEnabled = true;
      await _writeEnabled(true);
      await _syncPickupAlert();
      _publish();
      return true;
    });
  }

  Future<void> _syncPickupAlert() async {
    final schedule = _schedule;
    if (schedule == null) return;
    final pickup = schedule.pickupUtc?.toUtc();
    final id = JetlagAlertChannel.pickupNotificationId;
    if (pickup == null) {
      await alerts.cancel(id: id);
      return;
    }
    final fireAt = pickup.subtract(JetlagAlertChannel.pickupLead);
    if (!fireAt.isAfter(now())) {
      await alerts.cancel(id: id);
      return;
    }
    await alerts.schedulePickupReminder(
      id: id,
      whenUtc: fireAt,
      title: '픽업 준비',
      body: '${schedule.stationLabel} 픽업 90분 전입니다.',
    );
  }

  Future<void> _writeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(JetlagAlertChannel.enabledKey, enabled);
  }

  void _onHomeBaseChanged() {
    _publish();
  }

  JetLagTimeline _safeTimeline() {
    final schedule = _schedule;
    if (schedule == null) {
      throw StateError('Jet Lag Guide has no flight schedule');
    }
    try {
      return _calculator.calculate(
        schedule: schedule,
        lifestyle: lifestyle,
        logs: logs,
        sleepLogs: sleepLogs,
        settings: settings,
        now: now(),
        homeBaseTimezone: _home.homeBaseTimezone,
      );
    } catch (error, stack) {
      debugPrint('jetlag timeline fallback: $error\n$stack');
      return JetLagTimeline.unavailable(schedule);
    }
  }

  bool _current(int revision) => revision == _revision && !_disposed;

  void _publish() {
    if (_disposed) return;
    _timeline = _schedule == null ? null : _safeTimeline();
    notifyListeners();
  }

  Future<T> _lock<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _home.removeListener(_onHomeBaseChanged);
    _home.dispose();
    super.dispose();
  }
}
