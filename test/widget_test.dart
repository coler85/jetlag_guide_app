import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/logic/bunk_plan.dart';
import 'package:jetlag_guide_app/logic/guide_plan.dart';
import 'package:jetlag_guide_app/logic/jetlag_calculator.dart';
import 'package:jetlag_guide_app/logic/sleep_debt.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:jetlag_guide_app/main.dart';
import 'package:jetlag_guide_app/models/bunk_shift.dart';
import 'package:jetlag_guide_app/models/crew_log.dart';
import 'package:jetlag_guide_app/models/guide_event.dart';
import 'package:jetlag_guide_app/models/jetlag_schedule.dart';
import 'package:jetlag_guide_app/models/sleep_log.dart';
import 'package:jetlag_guide_app/models/lifestyle.dart';
import 'package:jetlag_guide_app/sample_schedule.dart';
import 'package:jetlag_guide_app/screens/jetlag_guide_shell.dart';
import 'package:jetlag_guide_app/screens/schedule_screen.dart';
import 'package:jetlag_guide_app/state/jetlag_guide_controller.dart';
import 'package:jetlag_guide_app/state/sleep_log_store.dart';
import 'package:jetlag_guide_app/theme/jetlag_theme.dart';
import 'package:jetlag_guide_app/screens/timeline_page.dart';
import 'package:jetlag_guide_app/widgets/sticky_timeline.dart';
import 'package:jetlag_guide_app/widgets/guide_event_card.dart';
import 'package:jetlag_guide_app/widgets/sleep_log_sheet.dart';
import 'package:provider/provider.dart';
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

  testWidgets('home without a schedule opens the intake screen', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('jetlag-schedule-page')), findsOneWidget);
    expect(kShowScheduleUpload, isFalse);
    expect(find.byKey(const ValueKey('schedule-action-file')), findsNothing);
    expect(find.byKey(const ValueKey('schedule-action-roster')), findsNothing);
    expect(
      find.byKey(const ValueKey('schedule-action-manual')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('schedule-action-report')), findsNothing);
    expect(find.byType(TimelinePage), findsNothing);

    await tester.tap(find.text('타임라인'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jetlag-empty-schedule')), findsOneWidget);
    expect(find.text('예시 일정 둘러보기'), findsOneWidget);

    await tester.tap(find.text('기록·설정'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jetlag-records-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('jetlag-empty-schedule'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('jetlag-schedule-page'), skipOffstage: false),
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

    await tester.tap(find.text('타임라인'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('예시 일정 둘러보기'));
    await tester.pumpAndSettle();

    expect(find.byType(TimelinePage), findsOneWidget);
    expect(find.text('예시 데이터입니다'), findsOneWidget);
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
    expect(clocks.supporting, '11:21 - 14:21 KST · 02:21Z - 05:21Z');
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

  test('UTC clock helpers put Z on a single instant and on both span ends', () {
    final instant = DateTime.utc(2026, 1, 15, 13, 30);
    expect(formatUtcHm(instant), '13:30');
    expect(formatUtcClock(instant), '13:30Z');
    expect(formatUtcSpan(instant, null), '13:30Z');
    expect(
      formatUtcSpan(
        DateTime.utc(2026, 1, 15, 8, 35),
        DateTime.utc(2026, 1, 15, 15, 35),
      ),
      '08:35Z - 15:35Z',
    );
    expect(
      formatRange(
        DateTime.utc(2026, 1, 15, 2, 21),
        DateTime.utc(2026, 1, 15, 5, 21),
        'UTC',
      ),
      '02:21Z–05:21Z',
    );
    expect(
      formatRange(
        DateTime.utc(2026, 1, 15, 2, 21),
        DateTime.utc(2026, 1, 15, 5, 21),
        'Etc/UTC',
      ),
      '02:21Z–05:21Z',
    );
    expect(
      formatHomeAndUtc(instant, 'Asia/Seoul'),
      '22:30 KST · 13:30Z',
    );
  });

  test('awake dashboard does not offer a wake time', () {
    final beforeCutoff = _timeline(DateTime.utc(2026, 6, 4, 4));
    expect(beforeCutoff.dashboard.sleeping, isFalse);
    expect(beforeCutoff.dashboard.stateLabel, '활동 중');
    expect(beforeCutoff.dashboard.cueLabel, '카페인 컷오프');

    final beforeSleep = _timeline(DateTime.utc(2026, 6, 4, 8));
    expect(beforeSleep.dashboard.sleeping, isFalse);
    expect(beforeSleep.dashboard.cueLabel, '다음 취침 계획');

    final asleep = _timeline(DateTime.utc(2026, 6, 4, 15));
    expect(asleep.dashboard.sleeping, isTrue);
    expect(asleep.dashboard.stateLabel, '수면 계획');
    expect(asleep.dashboard.cueLabel, '기상 계획');
  });

  test('bunk card sits immediately after departure', () {
    final markers = [
      for (final section in _timeline(DateTime.utc(2026, 6, 4, 12)).sections)
        ...section.markers,
    ];
    final departure = markers.indexWhere(
      (marker) =>
          marker is EventMarker &&
          marker.event.kind == GuideEventKind.departure,
    );
    expect(departure, greaterThanOrEqualTo(0));
    expect(markers[departure + 1], isA<BunkMarker>());
    final pickup = markers.indexWhere(
      (marker) =>
          marker is EventMarker && marker.event.kind == GuideEventKind.pickup,
    );
    expect(pickup, greaterThanOrEqualTo(0));
    expect(pickup, lessThan(departure));
    expect(markers[departure + 1].stamp.toUtc(), _laxLayover().stdUtc.toUtc());
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
    expect(find.text('다음 취침 계획'), findsOneWidget);
    expect(find.text('기상 계획'), findsNothing);
    expect(find.textContaining('6월 1일'), findsNothing);
    expect(find.byType(CustomScrollView), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('jetlag-now-line')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('jetlag-timeline')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.byKey(const ValueKey('jetlag-now-line')), findsOneWidget);

    final clock = tester.getRect(
      find.byKey(const ValueKey('jetlag-clock-bar')),
    );
    final caffeine = tester.getRect(find.byKey(const ValueKey('log-caffeine')));
    final scroll = tester.getRect(
      find.byKey(const ValueKey('jetlag-timeline')),
    );
    expect(clock.top, greaterThanOrEqualTo(scroll.top));
    expect(caffeine.bottom, lessThanOrEqualTo(clock.top));
    expect(clock.height, 24);
    expect(find.byKey(const ValueKey('jetlag-sleep-debt')), findsOneWidget);
    expect(find.byKey(const ValueKey('log-caffeine')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('jetlag-timeline')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    final pinnedClock = tester.getRect(
      find.byKey(const ValueKey('jetlag-clock-bar')),
    );
    final pinnedCaffeine = tester.getRect(
      find.byKey(const ValueKey('log-caffeine')),
    );
    final pinnedScroll = tester.getRect(
      find.byKey(const ValueKey('jetlag-timeline')),
    );
    expect(pinnedCaffeine.top, closeTo(pinnedScroll.top, 16));
    expect(pinnedClock.top, greaterThanOrEqualTo(pinnedCaffeine.bottom));
    expect(find.byKey(const ValueKey('log-caffeine')), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('jetlag-collapsing-header')))
          .height,
      lessThan(140),
    );
  });

  testWidgets('scrolling three days leaves one pinned date header', (
    tester,
  ) async {
    ensureJetlagTimeZones();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: StickyTimeline(
            header: SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedBarDelegate(),
            ),
            sections: [
              _dateSection('11월 24일 (화) · LAX', DateTime.utc(2026, 11, 24)),
              _dateSection('11월 25일 (수) · LAX', DateTime.utc(2026, 11, 25)),
              _dateSection(
                '11월 26일 (목) · LAX',
                DateTime.utc(2026, 11, 26, 12),
                lastTitle: '11월 26일 마지막',
              ),
            ],
            schedule: _laxLayover(),
            role: JetlagCrewRole.flightOps,
            bunkShift: null,
            onBunk: (_) {},
            onDismissLog: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('timeline-date-header')), findsOneWidget);
    expect(find.text('11월 24일 (화) · LAX'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('11월 26일 마지막'),
      400,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('jetlag-timeline')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('timeline-date-header')), findsOneWidget);
    expect(find.text('11월 26일 (목) · LAX'), findsOneWidget);
    expect(find.text('11월 24일 (화) · LAX'), findsNothing);
    expect(find.text('11월 25일 (수) · LAX'), findsNothing);
    final bar = tester.getRect(find.byKey(const ValueKey('test-pinned-bar')));
    final pinned = tester.getRect(
      find.byKey(const ValueKey('timeline-date-header')),
    );
    expect(pinned.top, closeTo(bar.bottom, 4));
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
    expect(find.text('수면 기록 없음'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('수면 기록 없음')).style?.color,
      isNot(JetlagTheme.debt),
    );

    await tester.tap(find.byKey(const ValueKey('log-sleep')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sleep-log-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('sleep-log-delete')), findsNothing);
    expect(find.text('잠든 시간'), findsOneWidget);
    expect(find.text('기상 시간'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sleep-log-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sleep-log-sheet')), findsNothing);
    expect(find.text('0분'), findsOneWidget);
    await _scrollToLoggedSleep(tester);
    _expectLoggedSleepBlock(tester);

    await tester.tap(find.text('기록·설정'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jetlag-user-settings')), findsOneWidget);
    expect(find.text('23:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('45분'), findsWidgets);
    expect(find.text('60분'), findsOneWidget);
    expect(find.text('하이브리드 모드 최대 이동 시간 · 3시간'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('60분'), findsWidgets);

    await tester.scrollUntilVisible(
      find.byIcon(Icons.close),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('jetlag-records-page')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(find.text('타임라인'));
    await tester.pumpAndSettle();
    expect(find.text('수면 기록 없음'), findsOneWidget);
    expect(find.text('0분'), findsNothing);
    expect(
      tester.widget<Text>(find.text('수면 기록 없음')).style?.color,
      isNot(JetlagTheme.debt),
    );
  });

  testWidgets('one saved sleep shows its shortfall and a logged block', (
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

    final controller = tester
        .element(find.byType(TimelinePage))
        .read<JetlagGuideController>();
    await controller.addSleepLog(
      startUtc: DateTime.utc(2026, 6, 4, 10, 15),
      endUtc: DateTime.utc(2026, 6, 4, 15, 45),
    );
    await tester.pumpAndSettle();

    expect(find.text('-1시간 30분'), findsOneWidget);
    expect(find.text('수면 기록 없음'), findsNothing);
    await _scrollToLoggedSleep(tester);
    _expectLoggedSleepBlock(tester);
    expect(find.text('기록 03:15–08:45'), findsOneWidget);
  });

  testWidgets('23:30 to 06:30 is overnight and save stays above the bars', (
    tester,
  ) async {
    ensureJetlagTimeZones();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);

    const now = '2026-06-04T12:00:00Z';
    SleepInterval? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await showSleepLogSheet(
                    context: context,
                    nowUtc: DateTime.parse(now),
                    usualSleep: const Duration(hours: 7),
                    iana: 'America/Los_Angeles',
                    zoneLabel: 'LAX',
                  );
                },
                child: const Text('열기'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarDatePicker), findsNothing);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('05:00'), findsOneWidget);
    _expectSaveAbove(tester, reservedBottom: 48);

    tester.view.viewInsets = const FakeViewPadding(bottom: 160);
    await tester.pump();
    _expectSaveAbove(tester, reservedBottom: 160);
    tester.view.resetViewInsets();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('sleep-log-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CalendarDatePicker), findsNothing);
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    await _advanceWheel(tester, column: 0, steps: 1);
    await _advanceWheel(tester, column: 1, steps: 30);
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sleep-log-end')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CalendarDatePicker), findsNothing);
    await _advanceWheel(tester, column: 0, steps: 1);
    await _advanceWheel(tester, column: 1, steps: 30);
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    expect(find.text('6월 2일 23:30 - 6월 3일 06:30'), findsOneWidget);
    _expectSaveAbove(tester, reservedBottom: 48);

    await tester.tap(find.byKey(const ValueKey('sleep-log-save')));
    await tester.pumpAndSettle();

    final interval = saved;
    expect(interval, isNotNull);
    final bed = wallClock(interval!.startUtc, 'America/Los_Angeles');
    final wake = wallClock(interval.endUtc, 'America/Los_Angeles');
    expect(bed.year, 2026);
    expect(bed.month, 6);
    expect(bed.day, 2);
    expect(bed.hour, 23);
    expect(bed.minute, 30);
    expect(wake.year, 2026);
    expect(wake.month, 6);
    expect(wake.day, 3);
    expect(wake.hour, 6);
    expect(wake.minute, 30);
    expect(
      DateTime.utc(
        wake.year,
        wake.month,
        wake.day,
      ).difference(DateTime.utc(bed.year, bed.month, bed.day)).inDays,
      1,
    );
  });

  test('a sleep record saved without an id still loads', () async {
    const key = 'LAX|2026-06-03T17:00:00.000Z|2026-06-05T17:00:00.000Z';
    SharedPreferences.setMockInitialValues({
      SleepLogStore.preferenceKey: jsonEncode([
        {
          'id': 'kept',
          'start': '2026-06-01T00:00:00.000Z',
          'end': '2026-06-01T06:00:00.000Z',
          'schedule': key,
        },
        {
          'start': '2026-06-04T10:15:00.000Z',
          'end': '2026-06-04T15:45:00.000Z',
          'schedule': key,
        },
        {
          'start': '2026-06-04T10:15:00.000Z',
          'end': '2026-06-04T15:45:00.000Z',
          'schedule': key,
        },
      ]),
    });

    const store = SleepLogStore();
    final logs = await store.load(key);
    final legacy = SleepLog.legacyId(
      startUtc: DateTime.utc(2026, 6, 4, 10, 15),
      endUtc: DateTime.utc(2026, 6, 4, 15, 45),
      scheduleKey: key,
    );
    expect(logs, hasLength(3));
    expect(logs.map((log) => log.id).toSet(), {legacy, '$legacy#2', 'kept'});
    final restored = logs.firstWhere((log) => log.id == legacy);
    expect(restored.startUtc, DateTime.utc(2026, 6, 4, 10, 15));
    expect(restored.endUtc, DateTime.utc(2026, 6, 4, 15, 45));

    final again = await store.load(key);
    expect(
      again.map((log) => log.id).toList()..sort(),
      logs.map((log) => log.id).toList()..sort(),
    );
    expect(
      SleepLog.tryParse({
        'start': '2026-06-04T15:00:00.000Z',
        'end': '2026-06-04T10:00:00.000Z',
      }),
      isNull,
    );
  });

  testWidgets('editing a logged sleep changes the debt and delete clears it', (
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

    final plannedTitle = find.descendant(
      of: find.byType(GuideEventCard),
      matching: find.text('수면'),
    );
    await _revealTimelineItem(tester, plannedTitle);
    final planned = find.ancestor(
      of: plannedTitle.first,
      matching: find.byType(GuideEventCard),
    );
    final plannedMark = tester.widget<Container>(
      find.descendant(of: planned, matching: find.byType(Container)),
    );
    expect((plannedMark.decoration! as BoxDecoration).color, JetlagTheme.sleep);
    await tester.tap(plannedTitle.first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sleep-log-sheet')), findsNothing);

    final controller = tester
        .element(find.byType(TimelinePage))
        .read<JetlagGuideController>();
    await controller.addSleepLog(
      startUtc: DateTime.utc(2026, 6, 4, 10, 15),
      endUtc: DateTime.utc(2026, 6, 4, 15, 45),
    );
    await tester.pumpAndSettle();
    expect(find.text('-1시간 30분'), findsOneWidget);
    final id = controller.sleepLogs.single.id;

    await _revealTimelineItem(tester, find.text('기록 03:15–08:45'));
    await tester.tap(find.text('기록 03:15–08:45'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sleep-log-delete')), findsOneWidget);
    expect(find.text('6월 4일 03:15 - 08:45'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sleep-log-end')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _advanceWheel(tester, column: 0, steps: 2);
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();
    expect(find.text('6월 4일 03:15 - 10:45'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sleep-log-save')));
    await tester.pumpAndSettle();
    expect(controller.sleepLogs.single.id, id);
    expect(
      controller.sleepLogs.single.endUtc,
      DateTime.utc(2026, 6, 4, 17, 45),
    );
    expect(find.text('0분'), findsOneWidget);
    expect(find.text('-1시간 30분'), findsNothing);

    await _revealTimelineItem(tester, find.text('기록 03:15–10:45'));
    await tester.tap(find.text('기록 03:15–10:45'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sleep-log-delete')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('sleep-log-delete-dialog')),
      findsOneWidget,
    );

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sleep-log-sheet')), findsOneWidget);
    expect(controller.sleepLogs, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('sleep-log-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sleep-log-delete-confirm')));
    await tester.pumpAndSettle();

    expect(controller.sleepLogs, isEmpty);
    final debt = const SleepDebtCalculator().evaluate(
      target: controller.settings.sleepTarget,
      logs: controller.sleepLogs,
    );
    expect(debt.balance, Duration.zero);
    expect(debt.recorded, isFalse);
    expect(find.text('수면 기록 없음'), findsOneWidget);
    expect(find.text('0분'), findsNothing);
    expect(find.text('기록한 수면'), findsNothing);
  });
}

void _expectSaveAbove(WidgetTester tester, {required double reservedBottom}) {
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  final save = tester.getRect(find.byKey(const ValueKey('sleep-log-save')));
  expect(save.top, greaterThanOrEqualTo(0));
  expect(save.bottom, lessThanOrEqualTo(height - reservedBottom));
  expect(save.height, greaterThan(40));
}

Future<void> _advanceWheel(
  WidgetTester tester, {
  required int column,
  required int steps,
}) async {
  final wheel = tester.widget<ListWheelScrollView>(
    find.byType(ListWheelScrollView).at(column),
  );
  final controller = wheel.controller!;
  controller.jumpTo(controller.offset + wheel.itemExtent * steps);
  await tester.pump();
}

Future<void> _scrollTimeline(WidgetTester tester, Finder finder) {
  return tester.scrollUntilVisible(
    finder,
    400,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('jetlag-timeline')),
      matching: find.byType(Scrollable),
    ),
  );
}

/// Scrolls [finder] to the middle of the timeline so a tap is not covered by
/// the pinned header or the bottom bar.
Future<void> _revealTimelineItem(WidgetTester tester, Finder finder) async {
  await _scrollTimeline(tester, finder);
  await Scrollable.ensureVisible(tester.element(finder.first), alignment: 0.5);
  await tester.pumpAndSettle();
}

Future<void> _scrollToLoggedSleep(WidgetTester tester) {
  return _scrollTimeline(tester, _loggedSleepLine());
}

Finder _loggedSleepLine() {
  return find.byWidgetPredicate((widget) {
    final data = widget is Text ? widget.data : null;
    if (data == null) return false;
    return data == '기록한 수면' || data.startsWith('기록 ');
  });
}

void _expectLoggedSleepBlock(WidgetTester tester) {
  final overlap = find.byKey(const ValueKey('sleep-overlap-card'));
  if (overlap.evaluate().isNotEmpty) {
    final log = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('sleep-overlap-log')),
        matching: find.byType(Text),
      ),
    );
    final plan = tester.widget<Text>(
      find.byKey(const ValueKey('sleep-overlap-plan')),
    );
    expect(log.style?.color, JetlagTheme.loggedSleep);
    expect(plan.style?.color, JetlagTheme.sleep);
    expect(log.style?.color, isNot(plan.style?.color));
    return;
  }
  final card = find.ancestor(
    of: find.text('기록한 수면'),
    matching: find.byType(GuideEventCard),
  );
  expect(card, findsOneWidget);
  final mark = tester.widget<Container>(
    find.descendant(of: card, matching: find.byType(Container)),
  );
  final color = (mark.decoration! as BoxDecoration).color;
  expect(color, JetlagTheme.loggedSleep);
  expect(color, isNot(JetlagTheme.sleep));
}

class _PinnedBarDelegate extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 104;

  @override
  double get maxExtent => 104;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return const ColoredBox(
      key: ValueKey('test-pinned-bar'),
      color: Color(0xFF111111),
      child: SizedBox.expand(),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return false;
  }
}

TimelineSection _dateSection(
  String heading,
  DateTime day, {
  String? lastTitle,
}) {
  return TimelineSection(
    dayKey: '${day.year}-${day.month}-${day.day}',
    heading: heading,
    markers: [
      for (var i = 0; i < 10; i++)
        EventMarker(
          event: GuideEvent(
            id: '$heading-$i',
            kind: GuideEventKind.meal,
            startUtc: day.add(Duration(hours: i)),
            title: i == 9 && lastTitle != null ? lastTitle : '일정 $i',
            detail: '블록',
          ),
          dimmed: false,
          dayKey: heading,
        ),
    ],
  );
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
    flightNumber: 'XX000',
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
