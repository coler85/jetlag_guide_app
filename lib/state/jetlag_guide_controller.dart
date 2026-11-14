import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/jetlag_calculator.dart';
import '../models/bunk_shift.dart';
import '../models/crew_log.dart';
import '../models/jetlag_schedule.dart';
import '../models/lifestyle.dart';
import '../notifications/jetlag_alert_channel.dart';
import '../notifications/jetlag_alert_scheduler.dart';
import 'jetlag_log_store.dart';
import 'jetlag_state.dart';

class JetlagGuideController extends ChangeNotifier {
  JetlagGuideController({
    required JetlagScheduleSnapshot schedule,
    required this.logStore,
    required this.alerts,
    DateTime Function()? now,
    JetLagState? homeBase,
    JetLagCalculator? calculator,
  }) : _schedule = schedule,
       _now = now ?? DateTime.now,
       role = schedule.crewRole,
       _home = homeBase ?? JetLagState(),
       _calculator = calculator ?? const JetLagCalculator() {
    _timeline = _safeTimeline();
    _home.addListener(_onHomeBaseChanged);
  }

  final JetlagLogStore logStore;
  final JetlagAlertScheduler alerts;
  final DateTime Function() _now;
  final JetLagState _home;
  final JetLagCalculator _calculator;

  JetlagScheduleSnapshot _schedule;
  JetlagCrewRole role;
  JetlagLifestyle lifestyle = JetlagLifestyle.kstAnchor;
  BunkShift? bunkShift;
  List<CrewLog> logs = const [];
  bool alertsEnabled = false;
  int _lifestyleEpoch = 0;
  bool _ready = false;
  bool _disposed = false;

  late JetLagTimeline _timeline;

  Future<void> _tail = Future<void>.value();
  int _serial = 0;

  /// Layover facts with the saved home base applied.
  JetlagScheduleSnapshot get schedule => _timeline.schedule;

  JetLagTimeline get timeline => _timeline;

  String get homeBaseTimezone => _home.homeBaseTimezone;

  bool get homeBaseRecovered => _home.recovered;

  /// False until preferences, including the home base, have been read.
  bool get isReady => _ready;

  DateTime now() => _now().toUtc();

  Future<void> load() {
    return _lock(() async {
      try {
        final epoch = _lifestyleEpoch;
        await _home.load();
        logs = await logStore.load(_schedule.key);
        final prefs = await SharedPreferences.getInstance();
        alertsEnabled = prefs.getBool(JetlagAlertChannel.enabledKey) ?? false;
        if (epoch == _lifestyleEpoch) {
          lifestyle = JetlagLifestyle.fromName(
            prefs.getString(JetlagLifestyle.preferenceKey),
          );
        }
      } catch (error, stack) {
        debugPrint('jetlag guide load failed: $error\n$stack');
      } finally {
        _ready = true;
        _publish();
      }
      if (_disposed || !alertsEnabled) return;
      final ready = await alerts.ensureChannel();
      if (ready && !_disposed) await _syncPickupAlert();
    });
  }

  void setHomeBaseTimezone(String iana) {
    unawaited(_home.setHomeBaseTimezone(iana));
  }

  Future<void> addLog(CrewLogKind kind) {
    return _lock(() async {
      final entry = CrewLog(
        id: '${now().microsecondsSinceEpoch}-${_serial++}',
        atUtc: now(),
        kind: kind,
        scheduleKey: _schedule.key,
      );
      final next = [...logs, entry];
      await logStore.save(_schedule.key, next);
      logs = next;
      _publish();
    });
  }

  Future<void> removeLog(String id) {
    return _lock(() async {
      final next = logs.where((log) => log.id != id).toList();
      await logStore.save(_schedule.key, next);
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
    return _lock(() async {
      _schedule = _schedule.copyWith(pickupUtc: pickupUtc.toUtc());
      _publish();
      if (alertsEnabled) await _syncPickupAlert();
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
    final pickup = _schedule.pickupUtc?.toUtc();
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
      body: '${_schedule.stationLabel} 픽업 90분 전입니다.',
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
    try {
      return _calculator.calculate(
        schedule: _schedule,
        lifestyle: lifestyle,
        logs: logs,
        now: now(),
        homeBaseTimezone: _home.homeBaseTimezone,
      );
    } catch (error, stack) {
      debugPrint('jetlag timeline fallback: $error\n$stack');
      return JetLagTimeline.unavailable(_schedule);
    }
  }

  void _publish() {
    if (_disposed) return;
    _timeline = _safeTimeline();
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
