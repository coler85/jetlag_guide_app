import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/logic/guide_plan.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:jetlag_guide_app/models/guide_event.dart';
import 'package:jetlag_guide_app/models/jetlag_schedule.dart';
import 'package:jetlag_guide_app/models/lifestyle.dart';
import 'package:jetlag_guide_app/models/user_settings.dart';
import 'package:jetlag_guide_app/state/user_settings_store.dart';
import 'package:jetlag_guide_app/widgets/user_settings_form.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Planned sleep placement for an anonymous SFO layover.
///
/// The first sleep follows arrival + arrivalToSleep. Middle layover days use
/// the selected mode's bedtime and wake. The last sleep ends at the
/// pre-departure wake.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ensureJetlagTimeZones();
  });

  const local = 'America/Los_Angeles';

  test('the first sleep after arrival lasts at least 90 minutes', () {
    final schedule = _sample();
    final sleeps = _sleepsAfter(schedule.staUtc, _events(schedule));

    expect(sleeps, isNotEmpty);
    expect(
      sleeps.first.endUtc!.difference(sleeps.first.startUtc),
      greaterThanOrEqualTo(const Duration(minutes: 90)),
    );
  });

  test('November 30 has a sleep block', () {
    final schedule = _sample();
    final sections = buildTimelineSections(
      schedule: schedule,
      logs: const [],
      now: DateTime.utc(2026, 11, 28),
      settings: UserSettings.defaults,
    );
    final november30 = sections.where(
      (section) => section.dayKey == '2026-11-30',
    );

    expect(
      november30.any(_sectionHasSleep),
      isTrue,
      reason: 'a sleep block should be grouped on 2026-11-30 $local',
    );
  });

  test('November 30 has a sleep block in each lifestyle mode', () {
    for (final lifestyle in [
      JetlagLifestyle.kstAnchor,
      JetlagLifestyle.hybrid,
    ]) {
      final sections = buildTimelineSections(
        schedule: _sample(),
        logs: const [],
        now: DateTime.utc(2026, 11, 28),
        settings: UserSettings.defaults,
        lifestyle: lifestyle,
      );
      final november30 = sections.where(
        (section) => section.dayKey == '2026-11-30',
      );

      expect(
        november30.any(_sectionHasSleep),
        isTrue,
        reason: '${lifestyle.name} should sleep on 2026-11-30 $local',
      );
    }
  });

  test('local adapt joins a pre-departure overlap when the gap is under 90 minutes', () {
    const settings = UserSettings.defaults;
    final schedule = _sample();
    final wake = _preDepartureWake(schedule, settings);
    final sleeps = _sleepsAfter(
      schedule.staUtc,
      _events(schedule, lifestyle: JetlagLifestyle.localAdapt),
    );
    final joined = sleeps.where((event) => event.endUtc == wake);

    expect(joined, hasLength(1));
    expect(joined.single.startUtc, DateTime.utc(2026, 12, 1, 10, 25));
    expect(
      joined.single.endUtc!.difference(joined.single.startUtc),
      const Duration(hours: 6),
    );
    expect(
      sleeps.where((event) {
        final end = event.endUtc;
        if (end == null || end == wake) return false;
        final gap = joined.single.startUtc.difference(end);
        return !gap.isNegative && gap < const Duration(minutes: 90);
      }),
      isEmpty,
    );
  });

  test(
    'local adapt keeps a night that ends 90 minutes or more before departure',
    () {
      final schedule = _sample();
      final wake = _preDepartureWake(schedule, UserSettings.defaults);
      final sleeps = _sleepsAfter(
        schedule.staUtc,
        _events(schedule, lifestyle: JetlagLifestyle.localAdapt),
      );
      final departure = sleeps.singleWhere((event) => event.endUtc == wake);
      final earlier = sleeps.where(
        (event) => event.endUtc != null && event.endUtc != wake,
      );

      expect(earlier, isNotEmpty);
      for (final sleep in earlier) {
        expect(
          departure.startUtc.difference(sleep.endUtc!),
          greaterThanOrEqualTo(const Duration(minutes: 90)),
        );
      }
    },
  );

  test('a 2 hour 59 minute gap merges into the later wake', () {
    final schedule = _gapSchedule();
    final events = _events(schedule, settings: _gapSettings(1));
    final sleeps = _sleepsAfter(schedule.staUtc, events);

    expect(sleeps, hasLength(1));
    expect(sleeps.single.endUtc, DateTime.utc(2026, 12, 1, 1));
    expect(sleeps.single.startUtc, DateTime.utc(2026, 11, 30, 22));
    expect(
      sleeps.single.endUtc!.difference(sleeps.single.startUtc),
      const Duration(hours: 3),
    );
  });

  test('a 3 hour gap stays two sleeps with a meal between them', () {
    final schedule = _gapSchedule();
    final events = _events(schedule, settings: _gapSettings(0));
    final sleeps = _sleepsAfter(schedule.staUtc, events);

    expect(sleeps, hasLength(2));
    expect(sleeps.first.endUtc, DateTime.utc(2026, 11, 30, 19));
    expect(sleeps.last.startUtc, DateTime.utc(2026, 11, 30, 22));
    expect(
      sleeps.last.startUtc.difference(sleeps.first.endUtc!),
      const Duration(hours: 3),
    );
    final meals = events.where((event) => event.kind == GuideEventKind.meal);
    expect(
      meals.where(
        (meal) =>
            meal.startUtc.isAfter(sleeps.first.endUtc!) &&
            meal.startUtc.isBefore(sleeps.last.startUtc),
      ),
      isNotEmpty,
    );
  });

  test(
    'the first sleep starts at or after arrival plus 2 hours 30 minutes',
    () {
      final schedule = _sample();
      final first = _sleepsAfter(schedule.staUtc, _events(schedule)).first;
      final earliest = schedule.staUtc.add(
        UserSettings.defaults.arrivalToSleep,
      );

      expect(
        UserSettings.defaults.arrivalToSleep,
        const Duration(hours: 2, minutes: 30),
      );
      expect(first.startUtc.isBefore(earliest), isFalse);
      expect(first.startUtc, DateTime.utc(2026, 11, 29, 20, 30));
    },
  );

  test('a 1 hour and a 4 hour delay move the first sleep start', () {
    final schedule = _sample();
    final atOneHour = _firstStart(
      schedule,
      const UserSettings(arrivalToSleep: Duration(hours: 1)),
    );
    final atFourHours = _firstStart(
      schedule,
      const UserSettings(arrivalToSleep: Duration(hours: 4)),
    );

    expect(
      atOneHour.isBefore(schedule.staUtc.add(const Duration(hours: 1))),
      isFalse,
    );
    expect(atOneHour, DateTime.utc(2026, 11, 29, 19));
    expect(
      atFourHours.isBefore(schedule.staUtc.add(const Duration(hours: 4))),
      isFalse,
    );
    expect(atFourHours, DateTime.utc(2026, 11, 30, 14));
    expect(atOneHour == atFourHours, isFalse);
  });

  test(
    'arrival-to-sleep defaults, snaps to 15 minutes, and is stored',
    () async {
      const store = UserSettingsStore();
      expect(
        (await store.load()).arrivalToSleep,
        const Duration(hours: 2, minutes: 30),
      );

      await store.save(const UserSettings(arrivalToSleep: Duration(hours: 1)));
      expect((await store.load()).arrivalToSleep, const Duration(hours: 1));

      await store.save(const UserSettings(arrivalToSleep: Duration(hours: 4)));
      expect((await store.load()).arrivalToSleep, const Duration(hours: 4));

      await store.save(
        const UserSettings(arrivalToSleep: Duration(minutes: 20)),
      );
      expect((await store.load()).arrivalToSleep, const Duration(hours: 1));

      await store.save(const UserSettings(arrivalToSleep: Duration(hours: 5)));
      expect((await store.load()).arrivalToSleep, const Duration(hours: 4));

      await store.save(
        const UserSettings(arrivalToSleep: Duration(hours: 2, minutes: 10)),
      );
      expect(
        (await store.load()).arrivalToSleep,
        const Duration(hours: 2, minutes: 15),
      );
    },
  );

  testWidgets('arrival-to-sleep sits beside commute with its help text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var settings = UserSettings.defaults;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return UserSettingsForm(
                settings: settings,
                onChanged: (next) => setState(() => settings = next),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('도착 후 잠들기까지'), findsOneWidget);
    expect(find.text('2시간 30분'), findsOneWidget);
    expect(find.text('하기, 입국, 호텔 이동, 짐 정리와 잘 준비까지 걸리는 시간'), findsOneWidget);
    expect(find.textContaining('의학'), findsNothing);

    final commute = tester.getTopLeft(
      find.byKey(const ValueKey('settings-commute')),
    );
    final arrival = tester.getTopLeft(
      find.byKey(const ValueKey('settings-arrival-to-sleep')),
    );
    expect(arrival.dy, greaterThan(commute.dy));

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('settings-arrival-to-sleep')),
        matching: find.byIcon(Icons.add_circle_outline),
      ),
    );
    await tester.pump();
    expect(settings.arrivalToSleep, const Duration(hours: 2, minutes: 45));
  });

  test('December 1 has a sleep that ends at the pre-departure wake', () {
    const settings = UserSettings.defaults;
    final schedule = _sample();
    final wake = _preDepartureWake(schedule, settings);

    expect(wake.isBefore(schedule.stdUtc), isTrue);
    expect(dayKey(wake, local), '2026-12-01');

    final match = _events(schedule).where(
      (event) =>
          event.kind == GuideEventKind.sleep &&
          event.endUtc == wake &&
          event.startUtc.isBefore(schedule.stdUtc),
    );
    expect(
      match,
      isNotEmpty,
      reason:
          'sleep should end at ${wake.toIso8601String()} '
          '(departure − show-up lead − prep − commute)',
    );
  });
}

/// Two blocks around a chosen gap. Wake 04:00 leaves 3 hours before the
/// pre-departure sleep. Wake 04:01 leaves 2 hours 59 minutes.
JetlagScheduleSnapshot _gapSchedule() {
  return JetlagScheduleSnapshot(
    stationLabel: 'SFO',
    localTimeZone: 'Asia/Seoul',
    referenceTimeZone: 'Asia/Seoul',
    staUtc: DateTime.utc(2026, 11, 30, 8),
    stdUtc: DateTime.utc(2026, 12, 1, 4, 20),
    flightNumber: 'XX000',
  );
}

UserSettings _gapSettings(int wakeMinute) {
  return UserSettings(
    defaultBedTime: const DayTime(hour: 23, minute: 0),
    defaultWakeTime: DayTime(hour: 4, minute: wakeMinute),
    chosenSleep: const Duration(hours: 4),
  );
}

JetlagScheduleSnapshot _sample() {
  final pickup = zonedUtc(
    iana: 'America/Los_Angeles',
    year: 2026,
    month: 11,
    day: 29,
    hour: 10,
    minute: 35,
  );
  final schedule = JetlagScheduleSnapshot(
    stationLabel: 'SFO',
    localTimeZone: 'America/Los_Angeles',
    referenceTimeZone: 'Asia/Seoul',
    staUtc: DateTime.utc(2026, 11, 29, 17, 35),
    stdUtc: DateTime.utc(2026, 12, 1, 19, 45),
    pickupUtc: pickup,
    flightNumber: 'XX000',
  );
  expect(schedule.staUtc, DateTime.utc(2026, 11, 29, 17, 35));
  expect(schedule.stdUtc, DateTime.utc(2026, 12, 1, 19, 45));
  expect(schedule.pickupUtc, DateTime.utc(2026, 11, 29, 18, 35));
  return schedule;
}

List<GuideEvent> _events(
  JetlagScheduleSnapshot schedule, {
  UserSettings settings = UserSettings.defaults,
  JetlagLifestyle lifestyle = JetlagLifestyle.kstAnchor,
}) {
  return buildGuideEvents(schedule, settings: settings, lifestyle: lifestyle);
}

DateTime _firstStart(JetlagScheduleSnapshot schedule, UserSettings settings) {
  return _sleepsAfter(
    schedule.staUtc,
    _events(schedule, settings: settings),
  ).first.startUtc;
}

List<GuideEvent> _sleepsAfter(DateTime arrival, List<GuideEvent> events) {
  final sta = arrival.toUtc();
  return events.where((event) {
    final end = event.endUtc?.toUtc();
    return event.kind == GuideEventKind.sleep &&
        end != null &&
        end.isAfter(sta);
  }).toList()..sort((a, b) => a.startUtc.compareTo(b.startUtc));
}

bool _sectionHasSleep(TimelineSection section) {
  return section.markers.whereType<EventMarker>().any(
    (marker) => marker.event.kind == GuideEventKind.sleep,
  );
}

/// Wake for the last sleep before the return departure.
///
/// Pickup − prep − commute is 16:50Z on the arrival day, which is before
/// STA, so a 90-minute cycle cannot start at arrival + commute. This sample
/// therefore uses departure − show-up lead − prep − commute.
DateTime _preDepartureWake(
  JetlagScheduleSnapshot schedule,
  UserSettings settings,
) {
  final prepAndCommute = settings.prepTime + settings.commuteTime;
  final earliestStart = schedule.staUtc.toUtc().add(settings.arrivalToSleep);
  final pickup = schedule.pickupUtc?.toUtc();
  if (pickup != null) {
    final fromPickup = pickup.subtract(prepAndCommute);
    final oneCycleStart = fromPickup.subtract(const Duration(minutes: 90));
    if (!oneCycleStart.isBefore(earliestStart)) return fromPickup;
  }
  final report = schedule.stdUtc.toUtc().subtract(settings.homeShowupLead);
  return report.subtract(prepAndCommute);
}
