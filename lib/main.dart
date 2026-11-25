import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'logic/jetlag_clock.dart';
import 'models/flight_schedule_input.dart';
import 'notifications/jetlag_alert_channel.dart';
import 'notifications/jetlag_alert_scheduler.dart';
import 'screens/root_screen.dart';
import 'state/jetlag_guide_controller.dart';
import 'state/jetlag_log_store.dart';
import 'state/jetlag_state.dart';
import 'theme/jetlag_theme.dart';

/// Values prepared before [runApp]. Either field may be null when startup
/// failed; the guide still opens and retries what it can.
class JetlagAppBootstrap {
  const JetlagAppBootstrap({this.preferences, this.notifications});

  final SharedPreferences? preferences;
  final FlutterLocalNotificationsPlugin? notifications;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SharedPreferences? preferences;
  FlutterLocalNotificationsPlugin? notifications;

  try {
    tzdata.initializeTimeZones();
    ensureJetlagTimeZones();
  } catch (error, stackTrace) {
    debugPrint('Jet Lag Guide: timezone init failed: $error\n$stackTrace');
  }

  try {
    preferences = await SharedPreferences.getInstance();
  } catch (error, stackTrace) {
    debugPrint('Jet Lag Guide: preferences init failed: $error\n$stackTrace');
  }

  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(JetlagAlertChannel.androidChannel);
    notifications = plugin;
  } catch (error, stackTrace) {
    debugPrint('Jet Lag Guide: notification init failed: $error\n$stackTrace');
  }

  runApp(
    MyApp(
      bootstrap: JetlagAppBootstrap(
        preferences: preferences,
        notifications: notifications,
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.bootstrap, this.schedule});

  final JetlagAppBootstrap? bootstrap;

  /// Layover injected by a roster app or a deep link. Null shows guidance.
  final FlightScheduleInput? schedule;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => _openGuide(bootstrap, schedule),
      child: MaterialApp(
        title: 'Jet Lag Guide',
        theme: JetlagTheme.material,
        darkTheme: JetlagTheme.material,
        themeMode: ThemeMode.dark,
        home: RootScreen(schedule: schedule),
      ),
    );
  }
}

JetlagGuideController _openGuide(
  JetlagAppBootstrap? bootstrap,
  FlightScheduleInput? schedule,
) {
  try {
    ensureJetlagTimeZones();
  } catch (error, stackTrace) {
    debugPrint('Jet Lag Guide: timezone retry failed: $error\n$stackTrace');
  }

  final preferences = bootstrap?.preferences;
  final controller = JetlagGuideController(
    schedule: schedule?.toSnapshot(),
    logStore: const JetlagLogStore(),
    alerts: JetlagLocalAlertScheduler(plugin: bootstrap?.notifications),
    homeBase: preferences == null
        ? null
        : JetLagState(loadPreferences: () async => preferences),
  );
  unawaited(controller.load());
  return controller;
}
