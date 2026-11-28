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

  test('local adapt skips a pre-departure sleep when pickup is daytime', () {
    const settings = UserSettings.defaults;
    final schedule = _sample();
    final wake = _preDepartureWake(schedule, settings);
    final sleeps = _sleepsAfter(
      schedule.staUtc,
      _events(schedule, lifestyle: JetlagLifestyle.localAdapt),
    );

    // Pickup is 10:35 SFO, outside the local 23:00–07:00 night.
    expect(sleeps.where((event) => event.endUtc == wake), isEmpty);
    expect(sleeps.where((event) => event.detail.contains('출발 전')), isEmpty);
    expect(sleeps, hasLength(2));
    expect(
      sleeps.where(
        (event) =>
            event.startUtc.toUtc().isAtSameMomentAs(
              DateTime.utc(2026, 12, 1, 7),
            ) &&
            event.endUtc!.toUtc().isAtSameMomentAs(
              DateTime.utc(2026, 12, 1, 15),
            ),
      ),
      hasLength(1),
    );
  });

  test('a daytime pickup leaves only the mode sleep', () {
    final schedule = _gapSchedule(
      zonedUtc(
        iana: 'Asia/Seoul',
        year: 2026,
        month: 11,
        day: 30,
        hour: 18,
        minute: 45,
      ),
    );
    final later = _events(schedule, settings: _gapSettings(1));
    final onTime = _events(schedule, settings: _gapSettings(0));
    final laterSleeps = _sleepsAfter(schedule.staUtc, later);
    final onTimeSleeps = _sleepsAfter(schedule.staUtc, onTime);

    // 18:45 KST is outside 23:00–04:00, so no pre-departure sleep is added.
    expect(laterSleeps, hasLength(1));
    expect(laterSleeps.single.endUtc, DateTime.utc(2026, 11, 30, 19, 1));
    expect(onTimeSleeps, hasLength(1));
    expect(onTimeSleeps.single.endUtc, DateTime.utc(2026, 11, 30, 19));
    expect(laterSleeps.where((event) => event.detail.contains('출발')), isEmpty);
    expect(onTimeSleeps.where((event) => event.detail.contains('출발')), isEmpty);
  });

  test('a 2 hour 59 minute gap merges into the later wake', () {
    final schedule = _nightGapSchedule();
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
    final schedule = _nightGapSchedule();
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

  test('a 02:45 KST pickup adds a pre-departure sleep and 18:45 does not', () {
    const detail = '출발 전 픽업에 맞춰 잡은 수면입니다';
    final night = _sample().copyWith(
      pickupUtc: zonedUtc(
        iana: 'Asia/Seoul',
        year: 2026,
        month: 12,
        day: 2,
        hour: 2,
        minute: 45,
      ),
    );
    final day = _sample().copyWith(
      pickupUtc: zonedUtc(
        iana: 'Asia/Seoul',
        year: 2026,
        month: 12,
        day: 1,
        hour: 18,
        minute: 45,
      ),
    );

    final nightSleeps = _sleepsAfter(night.staUtc, _events(night));
    final daySleeps = _sleepsAfter(day.staUtc, _events(day));

    expect(
      nightSleeps.where((event) => event.detail.contains(detail)),
      isNotEmpty,
    );
    expect(daySleeps.where((event) => event.detail.contains(detail)), isEmpty);
    expect(daySleeps, isNotEmpty);
    expect(
      daySleeps.map((event) => event.detail).join('\n').contains('출발 시각'),
      isFalse,
    );
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

  test('XX001 drops a 21:00-05:00 sleep that overlaps the departure duty', () {
    final schedule = _xx001LocalDeparture();
    const settings = UserSettings(
      defaultBedTime: DayTime(hour: 21, minute: 0),
      defaultWakeTime: DayTime(hour: 5, minute: 0),
    );
    final sleeps = _sleepsAfter(
      schedule.staUtc,
      _events(
        schedule,
        settings: settings,
        lifestyle: JetlagLifestyle.localAdapt,
      ),
    );
    final dutyStart = schedule.pickupUtc!;
    final dutyEnd = schedule.stdUtc.add(
      Duration(minutes: schedule.blockMinutes),
    );

    expect(
      sleeps.where((event) => _overlapsDuty(event, dutyStart, dutyEnd)),
      isEmpty,
    );
    expect(sleeps.where((event) => event.startUtc == _ams(28, 21, 0)), isEmpty);
    expect(sleeps.where((event) => event.endUtc == _ams(29, 5, 0)), isEmpty);
  });

  test('XX001 local adapt skips the home-night pre-departure sleep', () {
    final schedule = _xx001LocalDeparture();
    final sleeps = _sleepsAfter(
      schedule.staUtc,
      _events(schedule, lifestyle: JetlagLifestyle.localAdapt),
    );

    expect(
      sleeps.where(
        (event) =>
            event.startUtc == _ams(28, 10, 20) &&
            event.endUtc == _ams(28, 17, 20),
      ),
      isEmpty,
    );
    expect(sleeps.where((event) => event.detail.contains('출발 전')), isEmpty);
  });

  test('XX001 home-time mode keeps the pre-departure sleep', () {
    final schedule = _xx001LocalDeparture();
    final sleeps = _sleepsAfter(schedule.staUtc, _events(schedule));

    expect(
      sleeps.where(
        (event) =>
            event.startUtc == _ams(28, 10, 20) &&
            event.endUtc == _ams(28, 17, 20) &&
            event.detail.contains('출발 전'),
      ),
      hasLength(1),
    );
  });
}

/// XX001 leaves AMS at 21:15 with a 19:05 pickup. Inbound arrival is 15:00
/// the day before. Block is 11 hours, so the flight STA is 08:15 next morning.
JetlagScheduleSnapshot _xx001LocalDeparture() {
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

bool _overlapsDuty(GuideEvent event, DateTime dutyStart, DateTime dutyEnd) {
  final end = event.endUtc;
  if (end == null) return false;
  return event.startUtc.isBefore(dutyEnd) && dutyStart.isBefore(end);
}

/// Both clocks are Seoul. Wake 04:00 ends the mode night at 19:00Z.
/// Wake 04:01 ends it one minute later.
JetlagScheduleSnapshot _gapSchedule(DateTime? pickupUtc) {
  return JetlagScheduleSnapshot(
    stationLabel: 'SFO',
    localTimeZone: 'Asia/Seoul',
    referenceTimeZone: 'Asia/Seoul',
    staUtc: DateTime.utc(2026, 11, 30, 8),
    stdUtc: DateTime.utc(2026, 12, 1, 4, 20),
    pickupUtc: pickupUtc,
    flightNumber: 'XX000',
  );
}

/// 02:45 KST is inside 23:00–04:00, so a pre-departure sleep is built.
/// That pickup is before arrival, so its own wake cannot start after
/// arrival and the block still ends at departure − show-up − prep − commute.
JetlagScheduleSnapshot _nightGapSchedule() {
  return _gapSchedule(
    zonedUtc(
      iana: 'Asia/Seoul',
      year: 2026,
      month: 11,
      day: 30,
      hour: 2,
      minute: 45,
    ),
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
