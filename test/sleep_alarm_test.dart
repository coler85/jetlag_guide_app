import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/logic/guide_plan.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:jetlag_guide_app/models/guide_event.dart';
import 'package:jetlag_guide_app/models/jetlag_schedule.dart';
import 'package:jetlag_guide_app/models/lifestyle.dart';
import 'package:jetlag_guide_app/theme/jetlag_theme.dart';
import 'package:jetlag_guide_app/widgets/guide_event_card.dart';
import 'package:jetlag_guide_app/widgets/sleep_overlap_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ensureJetlagTimeZones);

  testWidgets(
    'XX001 pre-departure sleep shows alarm on the clock row, not in detail',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final schedule = _xx001();
      final event = buildGuideEvents(
        schedule,
        lifestyle: JetlagLifestyle.kstAnchor,
      ).singleWhere(
        (item) =>
            item.kind == GuideEventKind.sleep &&
            item.startUtc == _ams(28, 10, 20) &&
            item.endUtc == _ams(28, 17, 20) &&
            item.detail.contains('출발 전'),
      );

      expect(event.detail.contains('알람 기상'), isFalse);
      expect(event.alarmWakeUtc, event.endUtc);

      final clocks = formatTripleClock(
        startUtc: event.startUtc,
        endUtc: event.endUtc,
        localIana: schedule.localTimeZone,
        localTag: schedule.stationLabel,
        homeIana: schedule.referenceTimeZone,
      );
      final homeClock = formatHomeSpan(
        event.startUtc,
        event.endUtc,
        schedule.referenceTimeZone,
      );
      final localWake = formatAlarmLocal(
        event.endUtc!,
        schedule.localTimeZone,
        schedule.stationLabel,
      );
      final homeWake = formatAlarmHome(
        event.endUtc!,
        schedule.referenceTimeZone,
      );

      final overflows = <String>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) {
          overflows.add(details.exceptionAsString());
        }
        previousOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousOnError);

      await tester.pumpWidget(
        MaterialApp(
          theme: JetlagTheme.material,
          home: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 360,
              child: GuideEventCard(
                event: event,
                localClock: clocks.local,
                supportingClock: clocks.supporting,
                localIana: schedule.localTimeZone,
                localTag: schedule.stationLabel,
                homeIana: schedule.referenceTimeZone,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('알람 기상'), findsNothing);
      expect(find.text(event.detail), findsOneWidget);
      expect(find.byKey(const ValueKey('sleep-alarm')), findsOneWidget);
      expect(find.byKey(const ValueKey('sleep-alarm-local')), findsOneWidget);
      expect(find.byKey(const ValueKey('sleep-alarm-home')), findsOneWidget);
      expect(find.text(localWake), findsOneWidget);
      expect(find.text(homeWake), findsOneWidget);
      expect(homeWake.contains(zoneAbbreviation(event.endUtc!, 'Asia/Seoul')), isTrue);
      expect(find.text(clocks.local), findsOneWidget);
      expect(find.text(homeClock), findsOneWidget);
      expect(homeClock.contains('Z'), isFalse);
      expect(find.text(clocks.supporting), findsNothing);
      expect(find.byIcon(Icons.alarm), findsOneWidget);
      expect(overflows, isEmpty);

      _expectSingleLine(tester, find.byKey(const ValueKey('sleep-clock-supporting')));
      _expectSingleLine(tester, find.byKey(const ValueKey('sleep-clock-local')));
      _expectSingleLine(tester, find.byKey(const ValueKey('sleep-alarm-home')));

      final local = tester.getRect(find.byKey(const ValueKey('sleep-clock-local')));
      final alarm = tester.getRect(find.byKey(const ValueKey('sleep-alarm')));
      final supporting = tester.getRect(
        find.byKey(const ValueKey('sleep-clock-supporting')),
      );
      final alarmHome = tester.getRect(
        find.byKey(const ValueKey('sleep-alarm-home')),
      );
      expect(alarm.left, greaterThan(local.right - 1));
      expect((local.top - alarm.top).abs(), lessThan(4));
      expect(supporting.top, greaterThanOrEqualTo(local.bottom - 1));
      expect(supporting.left, closeTo(local.left, 2));
      expect(supporting.right, lessThanOrEqualTo(alarmHome.left + 1));
      expect((supporting.top - alarmHome.top).abs(), lessThan(16));
    },
  );

  testWidgets('SleepOverlapCard shows alarm on the plan line only', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final wake = _ams(28, 17, 20);
    final plan = GuideEvent(
      id: 'sleep-plan',
      kind: GuideEventKind.sleep,
      startUtc: _ams(28, 10, 20),
      endUtc: wake,
      title: '수면',
      detail: '출발 전 픽업에 맞춰 잡은 수면입니다.',
    );
    final log = GuideEvent(
      id: 'sleep-log:1',
      kind: GuideEventKind.loggedSleep,
      startUtc: _ams(28, 9, 20),
      endUtc: _ams(28, 14, 20),
      title: '기록한 수면',
      detail: '기록',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: JetlagTheme.material,
        home: Scaffold(
          body: SleepOverlapCard(
            plan: plan,
            logs: [log],
            iana: 'Europe/Amsterdam',
            localTag: 'AMS',
            homeIana: 'Asia/Seoul',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sleep-alarm')), findsOneWidget);
    expect(
      find.text(formatAlarmLocal(wake, 'Europe/Amsterdam', 'AMS')),
      findsOneWidget,
    );
    expect(find.text(formatAlarmHome(wake, 'Asia/Seoul')), findsOneWidget);
    expect(find.textContaining('알람 기상'), findsNothing);
    expect(log.alarmWakeUtc, isNull);
  });

  test('logged sleep never exposes an alarm wake', () {
    final logged = GuideEvent(
      id: 'sleep-log:2',
      kind: GuideEventKind.loggedSleep,
      startUtc: DateTime.utc(2026, 11, 28, 9),
      endUtc: DateTime.utc(2026, 11, 28, 16),
      title: '기록한 수면',
      detail: '기록',
    );
    expect(logged.alarmWakeUtc, isNull);
  });
}

void _expectSingleLine(WidgetTester tester, Finder finder) {
  final text = tester.widget<Text>(finder);
  expect(text.maxLines, 1);
  expect(text.softWrap, isFalse);
  final style = text.style;
  final fontSize = style?.fontSize ?? 11;
  final height = style?.height ?? 1.0;
  expect(
    tester.getSize(finder).height,
    lessThanOrEqualTo(fontSize * height + 1.5),
  );
}

/// XX001 leaves AMS at 21:15 with a 19:05 pickup.
JetlagScheduleSnapshot _xx001() {
  return JetlagScheduleSnapshot(
    stationLabel: 'AMS',
    originLabel: 'ICN',
    localTimeZone: 'Europe/Amsterdam',
    referenceTimeZone: 'Asia/Seoul',
    staUtc: _ams(27, 15, 0),
    stdUtc: _ams(28, 21, 15),
    pickupUtc: _ams(28, 19, 5),
    flightNumber: 'XX001',
    blockMinutes: 11 * 60,
  );
}

DateTime _ams(int day, int hour, int minute) {
  return zonedUtc(
    iana: 'Europe/Amsterdam',
    year: 2026,
    month: 11,
    day: day,
    hour: hour,
    minute: minute,
  );
}
