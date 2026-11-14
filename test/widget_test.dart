import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/logic/bunk_plan.dart';
import 'package:jetlag_guide_app/logic/guide_plan.dart';
import 'package:jetlag_guide_app/logic/jetlag_calculator.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:jetlag_guide_app/main.dart';
import 'package:jetlag_guide_app/models/bunk_shift.dart';
import 'package:jetlag_guide_app/models/crew_log.dart';
import 'package:jetlag_guide_app/models/jetlag_schedule.dart';
import 'package:jetlag_guide_app/models/lifestyle.dart';
import 'package:jetlag_guide_app/sample_schedule.dart';
import 'package:jetlag_guide_app/screens/jetlag_guide_shell.dart';
import 'package:jetlag_guide_app/screens/timeline_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stored coffee logs read as caffeine', () {
    final log = CrewLog.tryParse({
      'id': '1',
      'at': '2026-01-01T00:00:00.000Z',
      'kind': 'coffee',
    });
    expect(log?.kind, CrewLogKind.caffeine);
    expect(log?.kind.label, '카페인');
  });

  test('flight deck rest windows follow the shift name', () {
    final schedule = sampleJetlagSchedule(now: DateTime.utc(2026, 1, 1, 12));
    expect(BunkShift.forRole(JetlagCrewRole.flightOps), [
      BunkShift.p1LateRest,
      BunkShift.p2EarlyRest,
    ]);
    expect(BunkShift.p1LateRest.label, 'P1 후반휴식');
    expect(BunkShift.p2EarlyRest.label, 'P2 전반휴식');

    final early = _sleepWindow(schedule, BunkShift.p2EarlyRest);
    final late = _sleepWindow(schedule, BunkShift.p1LateRest);
    final cruiseStart = schedule.stdUtc.toUtc().add(
      const Duration(minutes: 90),
    );
    expect(
      early.startsWith(formatHm(cruiseStart, schedule.localTimeZone)),
      isTrue,
    );
    expect(early == late, isFalse);
  });

  testWidgets('home without a schedule shows guidance', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('jetlag-empty-schedule')), findsOneWidget);
    expect(find.text('샘플 일정 보기'), findsOneWidget);
    expect(find.byType(TimelinePage), findsNothing);

    await tester.tap(find.text('기록·설정'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jetlag-records-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('jetlag-empty-schedule'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('sample schedule keeps each tab mounted', (tester) async {
    await tester.pumpWidget(MyApp(schedule: sampleFlightSchedule()));
    await tester.pumpAndSettle();

    expect(find.text('시차·컨디션'), findsOneWidget);
    expect(find.byType(TimelinePage), findsOneWidget);
    expect(find.byKey(const ValueKey('log-caffeine')), findsOneWidget);
    expect(find.text('카페인'), findsWidgets);
    expect(find.byKey(const ValueKey('jetlag-bottom-nav')), findsOneWidget);

    await tester.tap(find.text('스케줄'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jetlag-schedule-page')), findsOneWidget);
    expect(find.text('ICN'), findsOneWidget);
    expect(find.byType(TimelinePage, skipOffstage: false), findsOneWidget);

    await tester.tap(find.text('기록·설정'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jetlag-records-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('jetlag-schedule-page'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('sample preview replaces the empty schedule', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('샘플 일정 보기'));
    await tester.pumpAndSettle();

    expect(find.byType(TimelinePage), findsOneWidget);
    expect(find.byKey(const ValueKey('log-caffeine')), findsOneWidget);
  });

  test('clock math stays on UTC and renders three zones', () {
    final localNow = DateTime(2026, 6, 4, 13);
    expect(localNow.isUtc, isFalse);
    final timeline = _timeline(localNow);

    expect(timeline.schedule.staUtc.isUtc, isTrue);
    expect(timeline.schedule.stdUtc.isUtc, isTrue);
    expect(timeline.schedule.pickupUtc!.isUtc, isTrue);
    for (final event in timeline.events) {
      expect(event.startUtc.isUtc, isTrue);
      expect(event.endUtc == null || event.endUtc!.isUtc, isTrue);
    }

    final flat = [for (final section in timeline.sections) ...section.markers];
    final nowIndex = flat.indexWhere((marker) => marker is NowMarker);
    final nowMarker = flat[nowIndex] as NowMarker;
    expect(nowMarker.stamp.isUtc, isTrue);
    expect(nowMarker.stamp, localNow.toUtc());
    for (var i = 0; i < flat.length; i++) {
      final marker = flat[i];
      if (marker is NowMarker) continue;
      if (i < nowIndex) {
        expect(marker.stamp.toUtc().isAfter(nowMarker.stamp), isFalse);
      } else {
        expect(marker.stamp.toUtc().isBefore(nowMarker.stamp), isFalse);
      }
    }

    final clocks = formatTripleClock(
      startUtc: DateTime.utc(2026, 1, 15, 2, 21),
      endUtc: DateTime.utc(2026, 1, 15, 5, 21),
      localIana: 'America/Los_Angeles',
      localTag: 'LAX',
      homeIana: 'Asia/Seoul',
    );
    expect(clocks.local, '18:21 - 21:21 (LAX)');
    expect(clocks.supporting, '11:21 - 14:21 KST · 02:21 - 05:21Z');
    expect(
      formatCockpitLine(
        nowUtc: DateTime.utc(2026, 1, 15, 15, 51),
        localIana: 'America/Los_Angeles',
        homeIana: 'Asia/Seoul',
        stationLabel: 'LAX',
      ),
      '07:51 LAX (Local)  |  00:51 KST (Home)  |  15:51Z (UTC)',
    );
  });

  test('awake dashboard does not offer a wake time', () {
    final beforeCutoff = _timeline(DateTime.utc(2026, 6, 4, 4));
    expect(beforeCutoff.dashboard.sleeping, isFalse);
    expect(beforeCutoff.dashboard.stateLabel, '활동 중');
    expect(beforeCutoff.dashboard.cueLabel, '카페인 컷오프');

    final beforeSleep = _timeline(DateTime.utc(2026, 6, 4, 8));
    expect(beforeSleep.dashboard.sleeping, isFalse);
    expect(beforeSleep.dashboard.cueLabel, '다음 권장 취침');

    final asleep = _timeline(DateTime.utc(2026, 6, 4, 15));
    expect(asleep.dashboard.sleeping, isTrue);
    expect(asleep.dashboard.stateLabel, '수면 권장');
    expect(asleep.dashboard.cueLabel, '권장 기상');
  });

  test('a date with no events does not keep a header group', () {
    final sections = _timeline(DateTime.utc(2026, 6, 1, 19)).sections;
    expect(sections, isNotEmpty);
    for (final section in sections) {
      expect(section.hasDatedContent, isTrue, reason: section.heading);
      expect(section.heading.contains('6월 1일'), isFalse);
    }
    expect(
      sections.any(
        (section) => section.markers.any((marker) => marker is NowMarker),
      ),
      isTrue,
    );
  });

  testWidgets('clock bar stays above the scrolling timeline', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: JetlagGuideShell(
          schedule: _laxLayover(),
          now: () => DateTime.utc(2026, 6, 1, 19),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('jetlag-clock-bar')), findsOneWidget);
    expect(find.textContaining('(Local)'), findsOneWidget);
    expect(find.textContaining('(Home)'), findsOneWidget);
    expect(find.textContaining('Z (UTC)'), findsOneWidget);
    expect(find.text('카페인'), findsWidgets);
    expect(find.text('커피'), findsNothing);
    expect(find.text('카페인 컷오프'), findsOneWidget);
    expect(find.text('권장 기상'), findsNothing);
    expect(find.textContaining('6월 1일'), findsNothing);
    expect(find.byKey(const ValueKey('jetlag-now-line')), findsOneWidget);
    expect(find.byType(CustomScrollView), findsOneWidget);

    final clock = tester.getRect(
      find.byKey(const ValueKey('jetlag-clock-bar')),
    );
    final scroll = tester.getRect(
      find.byKey(const ValueKey('jetlag-timeline')),
    );
    expect(clock.bottom, lessThanOrEqualTo(scroll.top));
  });

  testWidgets('sleep chip saves an interval and settings stay editable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: JetlagGuideShell(
          schedule: _laxLayover(),
          now: () => DateTime.utc(2026, 6, 4, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('jetlag-sleep-debt')), findsOneWidget);
    expect(find.text('-3시간 45분'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('log-sleep')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sleep-log-sheet')), findsOneWidget);
    expect(find.text('잠든 시간'), findsOneWidget);
    expect(find.text('기상 시간'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sleep-log-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sleep-log-sheet')), findsNothing);
    expect(find.text('0분'), findsOneWidget);

    await tester.tap(find.text('기록·설정'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jetlag-user-settings')), findsOneWidget);
    expect(find.text('23:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('45분'), findsWidgets);
    expect(find.text('60분'), findsOneWidget);
    expect(
      find.text('하이브리드 모드 최대 이동 시간 · 3시간'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('60분'), findsWidgets);
  });
}

JetlagScheduleSnapshot _laxLayover() {
  return JetlagScheduleSnapshot(
    stationLabel: 'LAX',
    originLabel: 'ICN',
    localTimeZone: 'America/Los_Angeles',
    referenceTimeZone: 'Asia/Seoul',
    staUtc: DateTime.utc(2026, 6, 3, 17),
    stdUtc: DateTime.utc(2026, 6, 5, 17),
    pickupUtc: DateTime.utc(2026, 6, 4, 20),
    flightNumber: 'KE017',
  );
}

JetLagTimeline _timeline(DateTime now) {
  return const JetLagCalculator().calculate(
    schedule: _laxLayover(),
    lifestyle: JetlagLifestyle.kstAnchor,
    logs: const [],
    now: now,
    homeBaseTimezone: 'Asia/Seoul',
  );
}

String _sleepWindow(JetlagScheduleSnapshot schedule, BunkShift shift) {
  final sleep = buildBunkPlan(
    schedule,
    shift,
  ).where((cue) => cue.kind == BunkCueKind.sleep);
  return sleep.single.window;
}
