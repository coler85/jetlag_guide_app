import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/home_base_timezone.dart';

/// Loads the platform preferences used by [JetLagState].
typedef JetLagPrefsLoader = Future<SharedPreferences> Function();

/// Home-base timezone for the Jet Lag Guide.
///
/// The roster app keeps feature state in a [ChangeNotifier] that the guide
/// shell watches. [JetLagState] follows that pattern and stays inside
/// `lib/features/jetlag_guide/` — it is not registered on the app root.
/// [JetlagGuideController] owns one instance and rebuilds the timeline when
/// [homeBaseTimezone] changes.
///
/// Packages already declared in `pubspec.yaml` (do not add them again):
/// - `shared_preferences: ^2.3.5` — persists [homeBaseTimezone]
/// - `timezone: ^0.11.1` — IANA conversion via `TZDateTime`
///
/// `main` must call `initializeTimeZones()` from
/// `package:timezone/data/latest.dart` before the first timeline build.
/// `ensureJetlagTimeZones` repeats that init if the call was skipped.
class JetLagState extends ChangeNotifier {
  JetLagState({JetLagPrefsLoader? loadPreferences})
    : _loadPreferences = loadPreferences ?? SharedPreferences.getInstance;

  static const preferenceKey = 'jetlag_guide_home_base_timezone';

  final JetLagPrefsLoader _loadPreferences;

  SharedPreferences? _preferences;
  String homeBaseTimezone = kJetlagFallbackHomeBase;
  bool _loading = true;
  bool _recovered = false;
  bool _disposed = false;
  int _epoch = 0;

  bool get isLoading => _loading;

  /// True when a stored value was missing from the timezone database, or
  /// preferences could not be read, and the Seoul fallback was applied.
  bool get recovered => _recovered;

  Future<void> load() async {
    final epoch = _epoch;
    try {
      final prefs = await _loadPreferences();
      _preferences = prefs;
      if (epoch != _epoch || _disposed) return;
      final stored = prefs.getString(preferenceKey);
      final trimmed = stored?.trim() ?? '';
      final resolved = resolveHomeBaseTimezone(stored);
      homeBaseTimezone = resolved;
      _recovered = trimmed.isNotEmpty && trimmed != resolved;
    } catch (error, stack) {
      debugPrint('jetlag home base load failed: $error\n$stack');
      if (epoch != _epoch || _disposed) return;
      homeBaseTimezone = kJetlagFallbackHomeBase;
      _recovered = true;
    } finally {
      if (epoch == _epoch && !_disposed) {
        _loading = false;
        _emit();
      }
    }
  }

  /// Applies a zone immediately, then writes it. Invalid ids fall back.
  Future<void> setHomeBaseTimezone(String raw) async {
    final trimmed = raw.trim();
    final next = resolveHomeBaseTimezone(trimmed);
    final invalid = trimmed.isNotEmpty && next != trimmed;
    _epoch++;
    final epoch = _epoch;
    _loading = false;
    _recovered = invalid;
    final changed = next != homeBaseTimezone || invalid;
    homeBaseTimezone = next;
    if (changed && !_disposed) _emit();
    await _persist(next, epoch: epoch);
  }

  Future<void> _persist(String iana, {required int epoch}) async {
    if (_disposed || epoch != _epoch) return;
    try {
      final prefs = _preferences ?? await _loadPreferences();
      _preferences = prefs;
      if (_disposed || epoch != _epoch) return;
      await prefs.setString(preferenceKey, iana);
    } catch (error, stack) {
      debugPrint('jetlag home base save failed: $error\n$stack');
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
