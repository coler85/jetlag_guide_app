import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/logic/guide_plan.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:jetlag_guide_app/models/guide_event.dart';
import 'package:jetlag_guide_app/models/jetlag_schedule.dart';
import 'package:jetlag_guide_app/models/lifestyle.dart';
import 'package:jetlag_guide_app/models/sleep_log.dart';
import 'package:jetlag_guide_app/models/user_settings.dart';
import 'package:jetlag_guide_app/notifications/jetlag_alert_scheduler.dart';
import 'package:jetlag_guide_app/screens/timeline_page.dart';
import 'package:jetlag_guide_app/state/jetlag_guide_controller.dart';
import 'package:jetlag_guide_app/state/jetlag_log_store.dart';
import 'package:jetlag_guide_app/theme/jetlag_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const settings = UserSettings(
    defaultBedTime: DayTime(hour: 9, minute: 15),
    defaultWakeTime: DayTime(hour: 16, minute: 15),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ensureJetlagTimeZones();
  });

  testWidgets('an overlapping record shares one card and opens the editor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final schedule = _xx000();
    final planStart = _local(2026, 11, 30, 9, 15);
    final planEnd = _local(2026, 11, 30, 16, 15);
    final logStart = _local(2026, 11, 30, 8, 15);
    final logEnd = _local(2026, 11, 30, 13, 8);

    final planned = _plannedSleep(schedule, settings);
    expect(planned.startUtc, planStart);
    expect(planned.endUtc, planEnd);

    final controller = JetlagGuideController(
      schedule: schedule,
      logStore: const JetlagLogStore(),
      alerts: const _QuietAlerts(),
      now: () => DateTime.utc(2026, 11, 30, 18),
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.setLifestyle(JetlagLifestyle.localAdapt);
    controller.setUserSettings(settings);
    await controller.addSleepLog(startUtc: logStart, endUtc: logEnd);

    final storedPlan = _plannedSleep(
      schedule,
      settings,
      sleepLogs: controller.sleepLogs,
    );
    expect(storedPlan.endUtc, planEnd);

    await tester.pumpWidget(
      MaterialApp(
        theme: JetlagTheme.material,
        home: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => TimelinePage(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final planLine = find.text('수면 계획 09:15–16:15');
    final logLine = find.text('기록 08:15–13:08');
    final caption = find.text('계획보다 1시간 일찍 잠, 3시간 7분 일찍 깸');
    await tester.scrollUntilVisible(
      caption,
      400,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('jetlag-timeline')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sleep-overlap-card')), findsOneWidget);
    expect(planLine, findsOneWidget);
    expect(logLine, findsOneWidget);
    expect(caption, findsOneWidget);
    expect(tester.widget<Text>(planLine).style?.color, JetlagTheme.sleep);
    expect(tester.widget<Text>(logLine).style?.color, JetlagTheme.loggedSleep);
    expect(
      find.byKey(const ValueKey('sleep-overlap-plan-bar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sleep-overlap-log-bar')), findsOneWidget);
    final planBar = tester.getRect(
      find.byKey(const ValueKey('sleep-overlap-plan-bar')),
    );
    final logBar = tester.getRect(
      find.byKey(const ValueKey('sleep-overlap-log-bar')),
    );
    expect(planBar.left, greaterThan(logBar.left));
    expect(planBar.right, greaterThan(logBar.right));

    final joined = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('sleep-overlap-card')),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data ?? '')
        .join('\n');
    expect(joined.contains('좋음'), isFalse);
    expect(joined.contains('부족'), isFalse);

    await tester.tap(planLine);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sleep-log-sheet')), findsNothing);

    await tester.tap(logLine);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sleep-log-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('sleep-log-delete')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sleep-log-start')),
        matching: find.text('08:15'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sleep-log-end')),
        matching: find.text('13:08'),
      ),
      findsOneWidget,
    );
  });

  test('a record that misses the plan stays on its own card', () {
    final schedule = _xx000();
    final sections = buildTimelineSections(
      schedule: schedule,
      logs: const [],
      now: DateTime.utc(2026, 11, 28),
      lifestyle: JetlagLifestyle.localAdapt,
      settings: settings,
      sleepLogs: [
        SleepLog(
          id: 'apart',
          startUtc: _local(2026, 11, 30, 17, 0),
          endUtc: _local(2026, 11, 30, 18, 0),
          scheduleKey: schedule.key,
        ),
      ],
    );

    final markers = sections.expand((section) => section.markers);
    expect(markers.whereType<SleepOverlapMarker>(), isEmpty);
    expect(
      markers.whereType<EventMarker>().where(
        (marker) =>
            marker.event.kind == GuideEventKind.loggedSleep &&
            marker.event.title == '기록한 수면',
      ),
      isNotEmpty,
    );
    expect(
      markers.whereType<EventMarker>().where(
        (marker) =>
            marker.event.kind == GuideEventKind.sleep &&
            marker.event.startUtc == _local(2026, 11, 30, 9, 15) &&
            marker.event.endUtc == _local(2026, 11, 30, 16, 15),
      ),
      isNotEmpty,
    );
  });
}

GuideEvent _plannedSleep(
  JetlagScheduleSnapshot schedule,
  UserSettings settings, {
  List<SleepLog> sleepLogs = const [],
}) {
  final events = buildGuideEvents(
    schedule,
    lifestyle: JetlagLifestyle.localAdapt,
    settings: settings,
    sleepLogs: sleepLogs,
  );
  return events.firstWhere(
    (event) =>
        event.kind == GuideEventKind.sleep &&
        event.startUtc == _local(2026, 11, 30, 9, 15),
  );
}

/// XX000 into SFO, with the sample pickup on the arrival morning.
JetlagScheduleSnapshot _xx000() {
  return JetlagScheduleSnapshot(
    stationLabel: 'SFO',
    localTimeZone: 'America/Los_Angeles',
    referenceTimeZone: 'Asia/Seoul',
    staUtc: DateTime.utc(2026, 11, 29, 17, 35),
    stdUtc: DateTime.utc(2026, 12, 1, 19, 45),
    pickupUtc: DateTime.utc(2026, 11, 29, 18, 35),
    flightNumber: 'XX000',
  );
}

DateTime _local(int year, int month, int day, int hour, int minute) {
  return zonedUtc(
    iana: 'America/Los_Angeles',
    year: year,
    month: month,
    day: day,
    hour: hour,
    minute: minute,
  );
}

class _QuietAlerts implements JetlagAlertScheduler {
  const _QuietAlerts();

  @override
  Future<void> cancel({required int id}) async {}

  @override
  Future<void> cancelRange({required int start, required int count}) async {}

  @override
  Future<bool> ensureChannel() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> scheduleAlert({
    required int id,
    required DateTime whenUtc,
    required String title,
    required String body,
  }) async {}

  @override
  Future<bool> canScheduleExact() async => true;

  @override
  Future<void> requestExactAlarm() async {}

  @override
  Future<void> scheduleTestAlert({
    required DateTime whenUtc,
    required String localIana,
    required String homeIana,
  }) async {}
}
