import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:jetlag_guide_app/logic/layover_pickup.dart';
import 'package:jetlag_guide_app/main.dart';
import 'package:jetlag_guide_app/models/bunk_shift.dart';
import 'package:jetlag_guide_app/models/flight_leg.dart';
import 'package:jetlag_guide_app/models/flight_schedule_input.dart';
import 'package:jetlag_guide_app/models/jetlag_schedule.dart';
import 'package:jetlag_guide_app/models/user_settings.dart';
import 'package:jetlag_guide_app/widgets/manual_schedule_form.dart';
import 'package:jetlag_guide_app/widgets/user_settings_form.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ensureJetlagTimeZones();
  });

  test('a pickup lead keeps exact minutes and converts both ways', () {
    final departure = DateTime.utc(2026, 11, 28, 3);
    expect(pickupRelativeToDeparture(120), '출발 2시간 전');
    expect(pickupRelativeToDeparture(130), '출발 2시간 10분 전');
    expect(pickupRelativeToDeparture(127), '출발 2시간 7분 전');
    expect(
      pickupLeadMinutes(departure, DateTime.utc(2026, 11, 28, 0, 53)),
      127,
    );
    expect(
      pickupUtcFromLead(departure, 130),
      DateTime.utc(2026, 11, 28, 0, 50),
    );
    expect(stepPickupLead(127, 1), 137);
    expect(stepPickupLead(127, 1) % 10, isNot(0));
  });

  testWidgets('the pickup lead and the clock stay in step', (tester) async {
    FlightScheduleInput? saved;
    await _pump(
      tester,
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                saved = await Navigator.push<FlightScheduleInput>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManualScheduleForm(
                      timeZone: 'Asia/Seoul',
                      referenceTimeZone: 'Asia/Seoul',
                      initial: _pickupTrip(DateTime.utc(2026, 11, 28, 1)),
                    ),
                  ),
                );
              },
              child: const Text('열기'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('레이오버 현지 픽업'), findsNothing);
    expect(find.text('출발 2시간 전'), findsOneWidget);
    expect(find.text('11월 28일 · 02:00'), findsOneWidget);
    _expectLeadBesideClock(tester, '11월 28일 · 02:00');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('pickup-lead-controls')),
        matching: find.byIcon(Icons.add_circle_outline),
      ),
    );
    await tester.pump();

    expect(find.text('출발 2시간 10분 전'), findsOneWidget);
    expect(find.textContaining('01:50'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.layoverPickupUtc, DateTime.utc(2026, 11, 28, 0, 50));
  });

  testWidgets('a pickup clock off the 10-minute grid keeps its minutes', (
    tester,
  ) async {
    await _pump(
      tester,
      _formApp(initial: _pickupTrip(DateTime.utc(2026, 11, 28, 0, 53))),
    );

    expect(find.text('출발 2시간 7분 전'), findsOneWidget);
    expect(find.textContaining('2시간 10분'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('pickup-lead-controls')),
        matching: find.byIcon(Icons.add_circle_outline),
      ),
    );
    await tester.pump();
    expect(find.text('출발 2시간 17분 전'), findsOneWidget);
    expect(find.textContaining('01:43'), findsWidgets);
  });

  testWidgets('a layover without a return flight has no lead control', (
    tester,
  ) async {
    await _pump(
      tester,
      _formApp(
        initial: FlightScheduleInput(
          flightNumber: 'XX000',
          origin: 'BBB',
          destination: 'AAA',
          destinationTimeZone: 'Etc/UTC',
          sta: DateTime.utc(2026, 11, 22, 8),
          std: DateTime.utc(2026, 11, 22, 18),
          pickup: DateTime.utc(2026, 11, 22, 14),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('manual-layover-pickup')), findsOneWidget);
    expect(find.text('레이오버 현지 픽업'), findsNothing);
    expect(find.byKey(const ValueKey('pickup-lead-controls')), findsNothing);
    expect(find.textContaining('오는 편 출발'), findsNothing);
  });

  testWidgets('the pickup lead stays beside the clock on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _formApp(initial: _pickupTrip(DateTime.utc(2026, 11, 28, 1))),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('pickup-lead-controls')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('manual-schedule-scroll')),
            matching: find.byType(Scrollable),
          )
          .at(0),
    );
    expect(tester.takeException(), isNull);
    _expectLeadBesideClock(tester, '11월 28일 · 02:00');
    final lead = tester.getRect(
      find.byKey(const ValueKey('pickup-lead-controls')),
    );
    expect(lead.right, lessThanOrEqualTo(320));
    expect(lead.left, greaterThanOrEqualTo(0));
  });

  testWidgets('the form fits a phone width', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_formApp());
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('manual-schedule-scroll')),
      const Offset(0, -2400),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('manual-bunk-ret')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an airport code selects its zone, or a picker when unknown', (
    tester,
  ) async {
    await _pump(tester, _formApp());

    await tester.enterText(
      find.byKey(const ValueKey('manual-out-origin')),
      'icn',
    );
    await tester.pump();
    expect(find.text('ICN 시간대 · Asia/Seoul'), findsOneWidget);
    expect(find.byKey(const ValueKey('manual-zone-out-origin')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('manual-out-origin')),
      'zzz',
    );
    await tester.pump();
    expect(find.textContaining('ZZZ 시간대'), findsNothing);
    expect(
      find.byKey(const ValueKey('manual-zone-out-origin')),
      findsOneWidget,
    );
  });

  testWidgets('the return origin starts as the outbound destination', (
    tester,
  ) async {
    await _pump(tester, _formApp());

    await tester.enterText(
      find.byKey(const ValueKey('manual-out-destination')),
      'AMS',
    );
    await tester.pump();

    final origin = tester.widget<TextField>(
      find.byKey(const ValueKey('manual-ret-origin')),
    );
    expect(origin.controller!.text, 'AMS');
    expect(find.text('AMS 시간대 · Europe/Amsterdam'), findsWidgets);
  });

  testWidgets('home show-up, wake, and leaving home follow the lead', (
    tester,
  ) async {
    await _pump(tester, _formApp());

    await tester.enterText(
      find.byKey(const ValueKey('manual-out-origin')),
      'ICN',
    );
    await tester.pump();

    expect(find.textContaining('08:25'), findsWidgets);
    expect(find.textContaining('07:25'), findsWidgets);
    expect(find.textContaining('06:40'), findsWidgets);
    expect(find.text('ICN 현지'), findsWidgets);
    expect(find.byKey(const ValueKey('manual-home-revert')), findsNothing);
  });

  testWidgets('a manual home show-up can return to the lead', (tester) async {
    await _pump(
      tester,
      _formApp(
        initial: FlightScheduleInput.journey(
          outbound: FlightLeg(
            flightNumber: 'XX000',
            origin: 'ICN',
            destination: 'AMS',
            originTimeZone: 'Asia/Seoul',
            destinationTimeZone: 'Europe/Amsterdam',
            std: DateTime.utc(2026, 11, 26, 1),
            sta: DateTime.utc(2026, 11, 26, 12),
          ),
          homeShowup: DateTime.utc(2026, 11, 26, 0),
          referenceTimeZone: 'Asia/Seoul',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('09:00'), findsWidgets);
    await tester.ensureVisible(
      find.byKey(const ValueKey('manual-home-revert')),
    );
    await tester.tap(find.byKey(const ValueKey('manual-home-revert')));
    await tester.pump();

    expect(find.textContaining('08:25'), findsWidgets);
    expect(find.byKey(const ValueKey('manual-home-revert')), findsNothing);
  });

  testWidgets('each leg has its own bunk choice', (tester) async {
    FlightScheduleInput? saved;
    await _pump(
      tester,
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                saved = await Navigator.push<FlightScheduleInput>(
                  context,
                  MaterialPageRoute<FlightScheduleInput>(
                    builder: (_) => const ManualScheduleForm(
                      timeZone: 'Asia/Seoul',
                      referenceTimeZone: 'Asia/Seoul',
                    ),
                  ),
                );
              },
              child: const Text('열기'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('manual-bunk-out')), findsOneWidget);
    expect(find.byKey(const ValueKey('manual-bunk-ret')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('manual-out-origin')),
      'ICN',
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-out-destination')),
      'AMS',
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-ret-destination')),
      'ICN',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('manual-bunk-out')));
    await tester.tap(find.text('P1 후반휴식').first);
    await tester.ensureVisible(find.byKey(const ValueKey('manual-bunk-ret')));
    await tester.tap(find.text('P2 전반휴식').last);
    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    final journey = saved!;
    expect(journey.outboundBunk, BunkShift.p1LateRest);
    expect(journey.returnBunk, BunkShift.p2EarlyRest);
    expect(journey.outbound!.origin, 'ICN');
    expect(journey.outbound!.destination, 'AMS');
    expect(journey.returning!.origin, 'AMS');
    expect(journey.returning!.destination, 'ICN');
  });

  testWidgets('a return-only saved record opens', (tester) async {
    final legacy = FlightScheduleInput(
      flightNumber: 'XX000',
      origin: 'BBB',
      destination: 'AAA',
      destinationTimeZone: 'Etc/UTC',
      sta: DateTime.utc(2026, 11, 22, 8),
      std: DateTime.utc(2026, 11, 22, 18),
      pickup: DateTime.utc(2026, 11, 22, 16),
      showup: DateTime.utc(2026, 11, 22, 14),
    );

    await _pump(tester, _formApp(initial: legacy));

    expect(tester.takeException(), isNull);
    final flight = tester.widget<TextField>(
      find.byKey(const ValueKey('manual-ret-flight')),
    );
    final origin = tester.widget<TextField>(
      find.byKey(const ValueKey('manual-ret-origin')),
    );
    expect(flight.controller!.text, 'XX000');
    expect(origin.controller!.text, 'BBB');
    expect(find.text('가는 편 출발 후 계산'), findsOneWidget);
    expect(find.textContaining('BBB 현지'), findsWidgets);
  });

  testWidgets('the chosen sleep target steps by 30 minutes', (tester) async {
    var settings = UserSettings.defaults;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
            builder: (context, setState) {
              return UserSettingsForm(
                settings: settings,
                onChanged: (next) => setState(() => settings = next),
              );
            },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('내가 정한 수면 목표'), findsOneWidget);
    expect(find.text('7시간'), findsOneWidget);
    expect(find.textContaining('권장'), findsNothing);
    expect(find.textContaining('필요'), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('settings-sleep-target')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('settings-sleep-target')),
        matching: find.byIcon(Icons.add_circle_outline),
      ),
    );
    await tester.pump();

    expect(find.text('7시간 30분'), findsOneWidget);
    expect(settings.sleepTarget, const Duration(hours: 7, minutes: 30));

    await tester.ensureVisible(find.byKey(const ValueKey('settings-sleep-target')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('settings-sleep-target')),
        matching: find.byIcon(Icons.remove_circle_outline),
      ),
    );
    await tester.pump();

    expect(find.text('7시간'), findsOneWidget);
    expect(settings.sleepTarget, const Duration(hours: 7));
  });

  testWidgets('settings show the home-base show-up lead', (tester) async {
    var settings = UserSettings.defaults;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
            builder: (context, setState) {
              return UserSettingsForm(
                settings: settings,
                onChanged: (next) => setState(() => settings = next),
              );
            },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('홈베이스 쇼업 (출발 95분 전)'), findsOneWidget);
    expect(find.text('95분'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('settings-home-showup')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('settings-home-showup')),
        matching: find.byIcon(Icons.add_circle_outline),
      ),
    );
    await tester.pump();

    expect(find.text('홈베이스 쇼업 (출발 100분 전)'), findsOneWidget);
    expect(settings.homeShowupLead, const Duration(minutes: 100));

    await tester.ensureVisible(find.byKey(const ValueKey('settings-home-showup')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('settings-home-showup')),
        matching: find.byIcon(Icons.remove_circle_outline),
      ),
    );
    await tester.pump();

    expect(find.text('홈베이스 쇼업 (출발 95분 전)'), findsOneWidget);
    expect(settings.homeShowupLead, const Duration(minutes: 95));
  });

  testWidgets('editing a saved trip reopens both legs', (tester) async {
    await _pump(tester, const MyApp());

    await tester.tap(find.byKey(const ValueKey('schedule-action-manual')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('manual-out-origin')),
      'ICN',
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-out-destination')),
      'AMS',
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-ret-flight')),
      'XX001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-ret-destination')),
      'ICN',
    );
    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('스케줄'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-edit')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final back = tester.widget<TextField>(
      find.byKey(const ValueKey('manual-ret-flight')),
    );
    expect(back.controller!.text, 'XX001');
    expect(find.text('ICN 시간대 · Asia/Seoul'), findsWidgets);
    expect(find.text('AMS 시간대 · Europe/Amsterdam'), findsWidgets);
  });
}

void _expectLeadBesideClock(WidgetTester tester, String clock) {
  final time = tester.getRect(find.text(clock));
  final lead = tester.getRect(
    find.byKey(const ValueKey('pickup-lead-controls')),
  );
  expect((time.center.dy - lead.center.dy).abs(), lessThan(8));
}

FlightScheduleInput _pickupTrip(DateTime pickupUtc) {
  return FlightScheduleInput.journey(
    outbound: FlightLeg(
      flightNumber: 'XX000',
      origin: 'ICN',
      destination: 'AMS',
      originTimeZone: 'Asia/Seoul',
      destinationTimeZone: 'Europe/Amsterdam',
      std: DateTime.utc(2026, 11, 26, 1),
      sta: DateTime.utc(2026, 11, 26, 10),
    ),
    returning: FlightLeg(
      flightNumber: 'XX001',
      origin: 'ICN',
      destination: 'AMS',
      originTimeZone: 'Asia/Seoul',
      destinationTimeZone: 'Europe/Amsterdam',
      std: DateTime.utc(2026, 11, 28, 3),
      sta: DateTime.utc(2026, 11, 28, 12),
    ),
    layoverPickup: pickupUtc,
    referenceTimeZone: 'Asia/Seoul',
  );
}

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Widget _formApp({FlightScheduleInput? initial}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        return ManualScheduleForm(
          timeZone: 'Asia/Seoul',
          referenceTimeZone: 'Asia/Seoul',
          role: JetlagCrewRole.flightOps,
          initial: initial,
        );
      },
    ),
  );
}
