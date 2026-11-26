import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:jetlag_guide_app/main.dart';
import 'package:jetlag_guide_app/models/flight_leg.dart';
import 'package:jetlag_guide_app/models/flight_schedule_input.dart';
import 'package:jetlag_guide_app/models/jetlag_schedule.dart';
import 'package:jetlag_guide_app/models/user_settings.dart';
import 'package:jetlag_guide_app/notifications/jetlag_alert_scheduler.dart';
import 'package:jetlag_guide_app/screens/schedule_screen.dart';
import 'package:jetlag_guide_app/screens/timeline_page.dart';
import 'package:jetlag_guide_app/services/flight_schedule_link.dart';
import 'package:jetlag_guide_app/services/ke_roster_gateway.dart';
import 'package:jetlag_guide_app/services/schedule_file_picker.dart';
import 'package:jetlag_guide_app/services/schedule_parser_service.dart';
import 'package:jetlag_guide_app/services/schedule_report_mail.dart';
import 'package:jetlag_guide_app/state/flight_schedule_store.dart';
import 'package:jetlag_guide_app/state/jetlag_guide_controller.dart';
import 'package:jetlag_guide_app/state/jetlag_log_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('parseFile does not invent a layover', () async {
    const parser = ScheduleParserService();
    final input = await parser.parseFile(
      const ScheduleFileRef(name: 'roster.pdf', kind: ScheduleFileKind.pdf),
    );

    expect(input, isNull);
  });

  test('a saved schedule is restored by a new controller', () async {
    ensureJetlagTimeZones();
    final input = _anonymousLayover();
    final first = _guide();
    addTearDown(first.dispose);
    await first.adoptSchedule(input);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(FlightScheduleStore.preferenceKey);
    expect(raw, isNotNull);
    final json = Map<String, Object?>.from(jsonDecode(raw!) as Map);
    expect(json['flightNumber'], 'XX000');
    expect(json['sta'], '2026-11-22T08:00:00.000Z');
    expect(json['std'], '2026-11-22T18:00:00.000Z');
    expect(json['pickup'], '2026-11-22T14:00:00.000Z');
    expect(json['showup'], '2026-11-22T16:00:00.000Z');
    expect(raw.contains('+09'), isFalse);

    final second = _guide();
    addTearDown(second.dispose);
    await second.load();

    expect(second.hasSchedule, isTrue);
    expect(second.isSampleSchedule, isFalse);
    expect(second.schedule.flightNumber, 'XX000');
    expect(second.schedule.originLabel, 'AAA');
    expect(second.schedule.stationLabel, 'BBB');
    expect(second.schedule.localTimeZone, 'Etc/UTC');
    expect(second.schedule.staUtc, DateTime.utc(2026, 11, 22, 8));
    expect(second.schedule.stdUtc, DateTime.utc(2026, 11, 22, 18));
    expect(second.schedule.pickupUtc, DateTime.utc(2026, 11, 22, 14));
    expect(second.schedule.showupUtc, DateTime.utc(2026, 11, 22, 16));
    expect(second.schedule.staUtc.isUtc, isTrue);
    expect(second.schedule.stdUtc.isUtc, isTrue);
    expect(second.schedule.pickupUtc!.isUtc, isTrue);
    expect(second.role, JetlagCrewRole.cabin);
    expect(second.schedule.blockMinutes, 480);
  });

  test('a sample preview is not saved', () async {
    final first = _guide();
    addTearDown(first.dispose);
    await first.adoptSchedule(_anonymousLayover(), sample: true);

    expect(first.isSampleSchedule, isTrue);
    expect(first.schedule.flightNumber, 'XX000');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FlightScheduleStore.preferenceKey), isNull);

    final second = _guide();
    addTearDown(second.dispose);
    await second.load();
    expect(second.hasSchedule, isFalse);
  });

  test('report mail pre-fills the subject', () {
    final link = scheduleReportLink();
    expect(link.startsWith('mailto:$kScheduleReportEmail?subject='), isTrue);
    expect(link.contains('+'), isFalse);
    expect(link.contains('%20'), isTrue);
    expect(Uri.parse(link).queryParameters['subject'], kScheduleReportSubject);
  });

  test('deep link becomes a layover and rejects a broken one', () {
    ensureJetlagTimeZones();
    final input = FlightScheduleLink.tryParse(
      'jetlagguide://schedule?flight=ke017&origin=icn&destination=lax'
      '&tz=America/Los_Angeles'
      '&sta=2026-11-15T18:00:00.000Z'
      '&std=2026-11-16T16:00:00.000Z'
      '&pickup=2026-11-16T12:00:00.000Z'
      '&role=cabin&block=840',
    );

    expect(input, isNotNull);
    expect(input!.origin, 'ICN');
    expect(input.destination, 'LAX');
    expect(input.flightNumber, 'KE017');
    expect(input.stdUtc.isAfter(input.staUtc), isTrue);
    expect(input.pickupUtc, DateTime.utc(2026, 11, 16, 12));
    expect(input.blockMinutes, 840);
    expect(input.crewRole.name, 'cabin');
    expect(FlightScheduleLink.tryParse('https://example.com'), isNull);
    expect(
      FlightScheduleLink.tryParse(
        'jetlagguide://schedule?origin=ICN&destination=LAX'
        '&tz=America/Los_Angeles'
        '&sta=2026-11-16T16:00:00.000Z'
        '&std=2026-11-15T18:00:00.000Z',
      ),
      isNull,
    );
  });

  test('a legacy record round-trips and keeps both layover clocks', () {
    final raw = <String, Object?>{
      'flightNumber': 'XX000',
      'origin': 'AAA',
      'destination': 'BBB',
      'destinationTimeZone': 'Etc/UTC',
      'std': '2026-11-22T18:00:00.000Z',
      'sta': '2026-11-22T08:00:00.000Z',
      'pickup': '2026-11-22T16:00:00.000Z',
      'showup': '2026-11-22T14:00:00.000Z',
      'crewRole': 'cabin',
      'blockMinutes': 480,
      'referenceTimeZone': 'Etc/UTC',
    };

    final input = FlightScheduleInput.tryParse(raw);
    expect(input, isNotNull);
    expect(input!.homeShowupUtc, isNull);
    expect(input.layoverPickupUtc, DateTime.utc(2026, 11, 22, 14));
    expect(input.toSnapshot().pickupUtc, DateTime.utc(2026, 11, 22, 16));
    expect(input.toSnapshot().showupUtc, DateTime.utc(2026, 11, 22, 14));
    expect(input.effectiveHomeShowupUtc(UserSettings.defaults), isNull);

    final again = FlightScheduleInput.tryParse(input.toJson());
    expect(again, isNotNull);
    expect(again!.toJson(), raw);
    expect(again.homeShowupUtc, isNull);
    expect(again.layoverPickupUtc, DateTime.utc(2026, 11, 22, 14));
    expect(again.toSnapshot().pickupUtc, input.toSnapshot().pickupUtc);
    expect(again.toSnapshot().showupUtc, input.toSnapshot().showupUtc);

    final pickupEarlier = FlightScheduleInput.tryParse({
      ...raw,
      'pickup': '2026-11-22T13:00:00.000Z',
      'showup': '2026-11-22T15:00:00.000Z',
    })!;
    expect(pickupEarlier.layoverPickupUtc, DateTime.utc(2026, 11, 22, 13));
    expect(pickupEarlier.homeShowupUtc, isNull);
    expect(
      pickupEarlier.toSnapshot().pickupUtc,
      DateTime.utc(2026, 11, 22, 13),
    );
    expect(
      pickupEarlier.toSnapshot().showupUtc,
      DateTime.utc(2026, 11, 22, 15),
    );
    expect(pickupEarlier.toJson()['pickup'], '2026-11-22T13:00:00.000Z');
    expect(pickupEarlier.toJson()['showup'], '2026-11-22T15:00:00.000Z');
  });

  test('an empty home show-up is the outbound STD minus the lead', () {
    final input = _outboundJourney();
    expect(input.homeShowupUtc, isNull);
    expect(
      input.effectiveHomeShowupUtc(UserSettings.defaults),
      DateTime.utc(2026, 11, 22, 8, 25),
    );
    expect(
      input.effectiveHomeShowupUtc(
        const UserSettings(homeShowupLead: Duration(minutes: 60)),
      ),
      DateTime.utc(2026, 11, 22, 9),
    );
    expect(
      input.effectiveHomeShowupUtc(
        const UserSettings(homeShowupLead: Duration(minutes: 500)),
      ),
      DateTime.utc(2026, 11, 22, 6),
    );
  });

  test('leaving home and waking follow an automatic or entered show-up', () {
    ensureJetlagTimeZones();
    final settings = UserSettings.defaults;
    final automatic = _icnAmsJourney();
    final autoShowup = automatic.effectiveHomeShowupUtc(settings)!;
    expect(autoShowup, DateTime.utc(2026, 11, 25, 23, 25));
    expect(
      settings.departHomeUtc(autoShowup),
      DateTime.utc(2026, 11, 25, 22, 25),
    );
    expect(
      settings.wakeForShowupUtc(autoShowup),
      DateTime.utc(2026, 11, 25, 21, 40),
    );

    final entered = DateTime.utc(2026, 11, 26, 0);
    final manual = _icnAmsJourney(homeShowup: entered);
    final used = manual.effectiveHomeShowupUtc(settings)!;
    expect(used, entered);
    expect(settings.departHomeUtc(used), DateTime.utc(2026, 11, 25, 23));
    expect(settings.wakeForShowupUtc(used), DateTime.utc(2026, 11, 25, 22, 15));
  });

  test('AMS departure and arrival stay exact across the 2026 DST changes', () {
    ensureJetlagTimeZones();
    // Spring forward on 2026-03-29: 02:00 CET becomes 03:00 CEST.
    expect(
      _savedAms(year: 2026, month: 3, day: 29, hour: 1, minute: 30).staUtc,
      DateTime.utc(2026, 3, 29, 0, 30),
    );
    expect(
      _savedAms(
        year: 2026,
        month: 3,
        day: 29,
        hour: 3,
        minute: 30,
        departure: true,
      ).stdUtc,
      DateTime.utc(2026, 3, 29, 1, 30),
    );
    expect(
      _savedAms(year: 2026, month: 3, day: 28, hour: 12, minute: 0).staUtc,
      DateTime.utc(2026, 3, 28, 11),
    );
    expect(
      _savedAms(
        year: 2026,
        month: 3,
        day: 30,
        hour: 12,
        minute: 0,
        departure: true,
      ).stdUtc,
      DateTime.utc(2026, 3, 30, 10),
    );
    // Fall back on 2026-10-25: 03:00 CEST becomes 02:00 CET.
    expect(
      _savedAms(year: 2026, month: 10, day: 25, hour: 1, minute: 30).staUtc,
      DateTime.utc(2026, 10, 24, 23, 30),
    );
    expect(
      _savedAms(
        year: 2026,
        month: 10,
        day: 25,
        hour: 3,
        minute: 30,
        departure: true,
      ).stdUtc,
      DateTime.utc(2026, 10, 25, 2, 30),
    );
    expect(
      _savedAms(year: 2026, month: 10, day: 24, hour: 12, minute: 0).staUtc,
      DateTime.utc(2026, 10, 24, 10),
    );
    expect(
      _savedAms(
        year: 2026,
        month: 10,
        day: 26,
        hour: 12,
        minute: 0,
        departure: true,
      ).stdUtc,
      DateTime.utc(2026, 10, 26, 11),
    );
  });

  test('an entered home show-up wins over the lead', () {
    final entered = DateTime.utc(2026, 11, 22, 6, 40);
    final input = _outboundJourney(homeShowup: entered);
    expect(
      input.effectiveHomeShowupUtc(
        const UserSettings(homeShowupLead: Duration(minutes: 30)),
      ),
      entered,
    );
    expect(input.toSnapshot().showupUtc, entered);
    expect(input.toSnapshot().pickupUtc, isNull);
  });

  test('roster open reports when the app is missing', () async {
    final gateway = KeRosterGateway(
      canOpen: (_) async => false,
      openUri: (_) async => true,
    );
    addTearDown(gateway.dispose);
    expect(await gateway.open(), KeRosterOpenResult.notInstalled);
  });

  testWidgets('manual entry switches to the timeline', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('schedule-action-manual')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('manual-schedule-form')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('manual-out-origin')),
      'icn',
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-out-destination')),
      'lax',
    );
    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('manual-schedule-form')), findsNothing);
    expect(find.byType(TimelinePage), findsOneWidget);
    expect(find.byKey(const ValueKey('log-caffeine')), findsOneWidget);
  });

  testWidgets('unsupported airline report explains the mail', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('schedule-action-report')));
    await tester.pumpAndSettle();

    expect(find.text(kScheduleReportPrompt), findsOneWidget);
    expect(find.textContaining(kScheduleReportSubject), findsOneWidget);
    expect(find.text(kScheduleReportEmail), findsOneWidget);

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.text(kScheduleReportPrompt), findsNothing);
  });

  testWidgets('an entered schedule is on the timeline after restart', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp(key: ValueKey('save-first')));
    await tester.pumpAndSettle();
    await _enterAnonymous(tester);

    expect(find.byType(TimelinePage), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(FlightScheduleStore.preferenceKey),
      contains('XX000'),
    );

    await tester.pumpWidget(const MyApp(key: ValueKey('save-second')));
    await tester.pumpAndSettle();

    expect(find.byType(TimelinePage), findsOneWidget);
    await tester.tap(find.text('스케줄'));
    await tester.pumpAndSettle();
    expect(find.text('XX000'), findsOneWidget);
    expect(find.text('AAA'), findsOneWidget);
    expect(find.text('BBB'), findsOneWidget);
  });

  testWidgets('sample preview is not restored after restart', (tester) async {
    await tester.pumpWidget(const MyApp(key: ValueKey('sample-first')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('타임라인'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('샘플 일정 보기'));
    await tester.pumpAndSettle();

    expect(find.text('샘플 일정'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FlightScheduleStore.preferenceKey), isNull);

    await tester.pumpWidget(const MyApp(key: ValueKey('sample-second')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('jetlag-schedule-page')), findsOneWidget);
    expect(find.byType(TimelinePage), findsNothing);
    expect(find.text('샘플 일정'), findsNothing);
  });

  testWidgets('clearing a schedule returns to the guide', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await _enterAnonymous(tester);
    expect(find.byType(TimelinePage), findsOneWidget);

    await tester.tap(find.text('기록·설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clear-schedule')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clear-schedule-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('일정을 가져와 주세요'), findsOneWidget);
    expect(find.byKey(const ValueKey('jetlag-schedule-page')), findsOneWidget);
    expect(find.byType(TimelinePage), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FlightScheduleStore.preferenceKey), isNull);
  });

  testWidgets('file recognition opens manual entry', (tester) async {
    final controller = _guide();
    addTearDown(controller.dispose);
    final roster = KeRosterGateway(
      canOpen: (_) async => false,
      openUri: (_) async => false,
    );
    addTearDown(roster.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleScreen(
            controller: controller,
            roster: roster,
            onSchedule: (_) {},
            parser: const ScheduleParserService(),
            files: ScheduleFilePicker(
              readImage: () async => const ScheduleFileRef(
                name: 'roster.png',
                kind: ScheduleFileKind.image,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('schedule-action-file')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-source-image')));
    await _until(tester, find.byKey(const ValueKey('manual-schedule-form')));

    expect(
      ScheduleScreen.recognitionPending,
      '아직 파일 자동 인식은 준비 중입니다. 직접 입력으로 넣어 주세요.',
    );
    expect(find.text(ScheduleScreen.recognitionPending), findsOneWidget);
    expect(find.byKey(const ValueKey('manual-schedule-form')), findsOneWidget);
  });

  testWidgets('the schedule header opens the card for now and swipes', (
    tester,
  ) async {
    ensureJetlagTimeZones();
    final trip = _headerTrip();

    await _showSchedule(tester, trip, DateTime.utc(2026, 11, 26, 4));
    expect(
      find.byKey(const ValueKey('schedule-header-dot-0-on')),
      findsOneWidget,
    );
    expect(find.text('가는 편'), findsOneWidget);
    expect(find.text('XX000'), findsOneWidget);

    await _showSchedule(tester, trip, DateTime.utc(2026, 11, 26, 12));
    expect(
      find.byKey(const ValueKey('schedule-header-dot-1-on')),
      findsOneWidget,
    );
    expect(find.text('레이오버'), findsOneWidget);
    expect(find.text('현지 픽업'), findsNothing);
    expect(find.textContaining('픽업 16:50'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('schedule-header-page')),
      const Offset(-700, 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-header-dot-2-on')),
      findsOneWidget,
    );
    expect(find.text('오는 편'), findsOneWidget);
    expect(find.text('XX001'), findsOneWidget);

    await _showSchedule(tester, trip, DateTime.utc(2026, 11, 26, 19));
    expect(
      find.byKey(const ValueKey('schedule-header-dot-2-on')),
      findsOneWidget,
    );
    expect(find.text('AMS'), findsWidgets);
    expect(find.text('ICN'), findsWidgets);
  });

  testWidgets('the pickup sheet lead moves the pickup clock', (tester) async {
    ensureJetlagTimeZones();
    final controller = JetlagGuideController(
      logStore: const JetlagLogStore(),
      alerts: _SilentAlerts(),
      now: () => DateTime.utc(2026, 11, 26, 12),
    );
    final roster = KeRosterGateway(
      canOpen: (_) async => false,
      openUri: (_) async => true,
    );
    addTearDown(controller.dispose);
    addTearDown(roster.dispose);
    await controller.adoptSchedule(_headerTrip());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleScreen(
            controller: controller,
            roster: roster,
            onSchedule: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('픽업 시간 수정'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('pickup-time-sheet')), findsOneWidget);
    expect(find.text('출발 2시간 10분 전'), findsOneWidget);
    expect(find.text('11월 26일 · 16:50'), findsOneWidget);
    final clock = tester.getRect(find.text('11월 26일 · 16:50'));
    final lead = tester.getRect(
      find.byKey(const ValueKey('pickup-lead-controls')),
    );
    expect((clock.center.dy - lead.center.dy).abs(), lessThan(8));

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('pickup-lead-controls')),
        matching: find.byIcon(Icons.add_circle_outline),
      ),
    );
    await tester.pump();

    expect(find.text('출발 2시간 20분 전'), findsOneWidget);
    expect(find.text('11월 26일 · 16:40'), findsOneWidget);
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    expect(controller.schedule.pickupUtc, DateTime.utc(2026, 11, 26, 15, 40));
    expect(find.text('현지 픽업'), findsNothing);
  });

  testWidgets('a return-only record is one header card', (tester) async {
    ensureJetlagTimeZones();
    await _showSchedule(
      tester,
      FlightScheduleInput(
        flightNumber: 'XX000',
        origin: 'ICN',
        destination: 'AMS',
        destinationTimeZone: 'Europe/Amsterdam',
        referenceTimeZone: 'Asia/Seoul',
        sta: DateTime.utc(2026, 11, 26, 8),
        std: DateTime.utc(2026, 11, 26, 18),
      ),
      DateTime.utc(2026, 11, 26, 12),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('현재 일정'), findsOneWidget);
    expect(find.text('ICN'), findsOneWidget);
    expect(find.text('가는 편'), findsNothing);
    expect(find.text('오는 편'), findsNothing);
    expect(find.byKey(const ValueKey('schedule-header-dot-0')), findsNothing);
  });
}

FlightScheduleInput _headerTrip() {
  return FlightScheduleInput.journey(
    outbound: FlightLeg(
      flightNumber: 'XX000',
      origin: 'ICN',
      destination: 'AMS',
      originTimeZone: 'Asia/Seoul',
      destinationTimeZone: 'Europe/Amsterdam',
      std: DateTime.utc(2026, 11, 26, 1),
      sta: DateTime.utc(2026, 11, 26, 8),
    ),
    returning: FlightLeg(
      flightNumber: 'XX001',
      origin: 'AMS',
      destination: 'ICN',
      originTimeZone: 'Europe/Amsterdam',
      destinationTimeZone: 'Asia/Seoul',
      std: DateTime.utc(2026, 11, 26, 18),
      sta: DateTime.utc(2026, 11, 27, 4),
    ),
    layoverPickup: DateTime.utc(2026, 11, 26, 15, 50),
    referenceTimeZone: 'Asia/Seoul',
  );
}

Future<void> _showSchedule(
  WidgetTester tester,
  FlightScheduleInput input,
  DateTime now,
) async {
  final controller = JetlagGuideController(
    logStore: const JetlagLogStore(),
    alerts: _SilentAlerts(),
    now: () => now,
  );
  final roster = KeRosterGateway(
    canOpen: (_) async => false,
    openUri: (_) async => true,
  );
  addTearDown(controller.dispose);
  addTearDown(roster.dispose);
  await controller.adoptSchedule(input);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ScheduleScreen(
          controller: controller,
          roster: roster,
          onSchedule: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FlightScheduleInput _icnAmsJourney({DateTime? homeShowup}) {
  return FlightScheduleInput.journey(
    outbound: FlightLeg(
      flightNumber: 'XX000',
      origin: 'ICN',
      destination: 'AMS',
      originTimeZone: 'Asia/Seoul',
      destinationTimeZone: 'Europe/Amsterdam',
      std: zonedUtc(
        iana: 'Asia/Seoul',
        year: 2026,
        month: 11,
        day: 26,
        hour: 10,
        minute: 0,
      ),
      sta: zonedUtc(
        iana: 'Europe/Amsterdam',
        year: 2026,
        month: 11,
        day: 26,
        hour: 15,
        minute: 0,
      ),
    ),
    returning: FlightLeg(
      flightNumber: 'XX001',
      origin: 'AMS',
      destination: 'ICN',
      originTimeZone: 'Europe/Amsterdam',
      destinationTimeZone: 'Asia/Seoul',
      std: zonedUtc(
        iana: 'Europe/Amsterdam',
        year: 2026,
        month: 11,
        day: 28,
        hour: 10,
        minute: 0,
      ),
      sta: zonedUtc(
        iana: 'Asia/Seoul',
        year: 2026,
        month: 11,
        day: 29,
        hour: 6,
        minute: 0,
      ),
    ),
    homeShowup: homeShowup,
    referenceTimeZone: 'Asia/Seoul',
  );
}

/// XX000 arrives at AMS, or XX001 leaves AMS, then the journey is read back.
FlightLeg _savedAms({
  required int year,
  required int month,
  required int day,
  required int hour,
  required int minute,
  bool departure = false,
}) {
  final ams = zonedUtc(
    iana: 'Europe/Amsterdam',
    year: year,
    month: month,
    day: day,
    hour: hour,
    minute: minute,
  );
  final outboundSta = departure ? ams.subtract(const Duration(hours: 20)) : ams;
  final returnStd = departure ? ams : ams.add(const Duration(hours: 30));
  final input = FlightScheduleInput.journey(
    outbound: FlightLeg(
      flightNumber: 'XX000',
      origin: 'ICN',
      destination: 'AMS',
      originTimeZone: 'Asia/Seoul',
      destinationTimeZone: 'Europe/Amsterdam',
      std: outboundSta.subtract(const Duration(hours: 11)),
      sta: outboundSta,
    ),
    returning: FlightLeg(
      flightNumber: 'XX001',
      origin: 'AMS',
      destination: 'ICN',
      originTimeZone: 'Europe/Amsterdam',
      destinationTimeZone: 'Asia/Seoul',
      std: returnStd,
      sta: returnStd.add(const Duration(hours: 11)),
    ),
    referenceTimeZone: 'Asia/Seoul',
  );
  final again = FlightScheduleInput.tryParse(input.toJson());
  expect(again, isNotNull);
  return departure ? again!.returning! : again!.outbound!;
}

FlightScheduleInput _outboundJourney({DateTime? homeShowup}) {
  return FlightScheduleInput.journey(
    outbound: FlightLeg(
      flightNumber: 'XX000',
      origin: 'ICN',
      destination: 'AMS',
      destinationTimeZone: 'Europe/Amsterdam',
      std: DateTime.utc(2026, 11, 22, 10),
      sta: DateTime.utc(2026, 11, 22, 21),
    ),
    homeShowup: homeShowup,
  );
}

FlightScheduleInput _anonymousLayover() {
  return FlightScheduleInput(
    flightNumber: 'XX000',
    origin: 'AAA',
    destination: 'BBB',
    destinationTimeZone: 'Etc/UTC',
    referenceTimeZone: 'Etc/UTC',
    sta: DateTime.parse('2026-11-22T17:00:00+09:00'),
    std: DateTime.parse('2026-11-23T03:00:00+09:00'),
    pickup: DateTime.parse('2026-11-22T23:00:00+09:00'),
    showup: DateTime.parse('2026-11-23T01:00:00+09:00'),
    crewRole: JetlagCrewRole.cabin,
    blockMinutes: 480,
  );
}

JetlagGuideController _guide() {
  return JetlagGuideController(
    logStore: const JetlagLogStore(),
    alerts: _SilentAlerts(),
  );
}

class _SilentAlerts implements JetlagAlertScheduler {
  @override
  Future<void> cancel({required int id}) async {}

  @override
  Future<bool> ensureChannel() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedulePickupReminder({
    required int id,
    required DateTime whenUtc,
    required String title,
    required String body,
  }) async {}
}

Future<void> _enterAnonymous(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('schedule-action-manual')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('manual-out-origin')),
    'aaa',
  );
  await tester.enterText(
    find.byKey(const ValueKey('manual-out-destination')),
    'bbb',
  );
  await tester.ensureVisible(find.byKey(const ValueKey('manual-out-flight')));
  await tester.enterText(
    find.byKey(const ValueKey('manual-out-flight')),
    'xx000',
  );
  await tester.tap(find.byKey(const ValueKey('manual-save')));
  await tester.pumpAndSettle();
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
}
