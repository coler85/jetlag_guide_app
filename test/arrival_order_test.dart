import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/logic/guide_plan.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:jetlag_guide_app/logic/lifestyle_plan.dart';
import 'package:jetlag_guide_app/logic/sleep_constants.dart';
import 'package:jetlag_guide_app/models/arrival_order.dart';
import 'package:jetlag_guide_app/models/flight_leg.dart';
import 'package:jetlag_guide_app/models/guide_event.dart';
import 'package:jetlag_guide_app/models/jetlag_schedule.dart';
import 'package:jetlag_guide_app/models/lifestyle.dart';
import 'package:jetlag_guide_app/models/user_settings.dart';
import 'package:jetlag_guide_app/state/user_settings_store.dart';
import 'package:jetlag_guide_app/widgets/user_settings_form.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ensureJetlagTimeZones();
  });

  group('ArrivalOrder settings', () {
    test('defaults to auto and copyWith/== work', () {
      expect(UserSettings.defaults.arrivalOrder, ArrivalOrder.auto);
      final rest = UserSettings.defaults.copyWith(
        arrivalOrder: ArrivalOrder.restFirst,
      );
      expect(rest.arrivalOrder, ArrivalOrder.restFirst);
      expect(rest == UserSettings.defaults, isFalse);
      expect(
        rest.copyWith(arrivalOrder: ArrivalOrder.auto),
        UserSettings.defaults,
      );
      expect(ArrivalOrder.fromName(null), ArrivalOrder.auto);
      expect(ArrivalOrder.fromName('nope'), ArrivalOrder.auto);
      expect(ArrivalOrder.fromName('mealFirst'), ArrivalOrder.mealFirst);
      expect(ArrivalOrder.auto.label, '자동');
      expect(ArrivalOrder.restFirst.label, '먼저 휴식');
      expect(ArrivalOrder.mealFirst.label, '먼저 식사');
    });

    test('store saves, restores, and falls back unknown to auto', () async {
      const store = UserSettingsStore();
      expect((await store.load()).arrivalOrder, ArrivalOrder.auto);

      await store.save(
        UserSettings.defaults.copyWith(arrivalOrder: ArrivalOrder.mealFirst),
      );
      expect((await store.load()).arrivalOrder, ArrivalOrder.mealFirst);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(UserSettingsStore.arrivalOrderKey, 'mystery');
      expect((await store.load()).arrivalOrder, ArrivalOrder.auto);
    });
  });

  group('settings form arrival order', () {
    testWidgets('shows three choices at 360dp without overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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

      expect(find.text('도착 후 순서'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-arrival-order')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('settings-arrival-order-rest')));
      await tester.pumpAndSettle();
      expect(settings.arrivalOrder, ArrivalOrder.restFirst);

      await tester.tap(find.byKey(const ValueKey('settings-arrival-order-meal')));
      await tester.pumpAndSettle();
      expect(settings.arrivalOrder, ArrivalOrder.mealFirst);

      await tester.tap(find.byKey(const ValueKey('settings-arrival-order-auto')));
      await tester.pumpAndSettle();
      expect(settings.arrivalOrder, ArrivalOrder.auto);
      expect(tester.takeException(), isNull);
    });
  });

  group('arrival parts settings', () {
    test('defaults split 30/60/60 and hotelArrival is STA+90', () {
      final s = UserSettings.defaults;
      expect(s.arrivalDeboard, const Duration(minutes: 30));
      expect(s.hotelTransfer, const Duration(minutes: 60));
      expect(s.afterHotelReady, const Duration(minutes: 60));
      expect(s.arrivalToSleep, const Duration(hours: 2, minutes: 30));
      expect(s.hotelArrivalDelay, const Duration(minutes: 90));
      final sta = DateTime.utc(2026, 11, 30, 8);
      expect(s.hotelArrivalUtc(sta), DateTime.utc(2026, 11, 30, 9, 30));
    });

    test('splitArrivalToSleep migrates 150→30/60/60 and keeps sum', () {
      final def = UserSettings.splitArrivalToSleep(
        const Duration(hours: 2, minutes: 30),
      );
      expect(def.deboard, const Duration(minutes: 30));
      expect(def.transfer, const Duration(minutes: 60));
      expect(def.ready, const Duration(minutes: 60));

      for (final total in [60, 75, 90, 120, 180, 210, 240]) {
        final parts = UserSettings.splitArrivalToSleep(Duration(minutes: total));
        final sum =
            parts.deboard.inMinutes +
            parts.transfer.inMinutes +
            parts.ready.inMinutes;
        expect(sum, total);
        expect(parts.deboard.inMinutes % 15, 0);
        expect(parts.transfer.inMinutes % 15, 0);
        expect(parts.ready.inMinutes % 15, 0);
      }
    });

    test('store migrates legacy total and saves three parts', () async {
      const store = UserSettingsStore();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(UserSettingsStore.arrivalToSleepKey, 150);
      final loaded = await store.load();
      expect(loaded.arrivalDeboard, const Duration(minutes: 30));
      expect(loaded.hotelTransfer, const Duration(minutes: 60));
      expect(loaded.afterHotelReady, const Duration(minutes: 60));
      expect(loaded.arrivalToSleep, const Duration(hours: 2, minutes: 30));

      await prefs.clear();
      await prefs.setInt(UserSettingsStore.arrivalToSleepKey, 180);
      final custom = await store.load();
      expect(
        custom.arrivalDeboard.inMinutes +
            custom.hotelTransfer.inMinutes +
            custom.afterHotelReady.inMinutes,
        180,
      );
      expect(custom.arrivalDeboard.inMinutes % 15, 0);

      await store.save(
        UserSettings.defaults.copyWith(
          arrivalDeboard: const Duration(minutes: 45),
          hotelTransfer: const Duration(minutes: 45),
          afterHotelReady: const Duration(minutes: 75),
        ),
      );
      final again = await store.load();
      expect(again.arrivalDeboard, const Duration(minutes: 45));
      expect(again.hotelTransfer, const Duration(minutes: 45));
      expect(again.afterHotelReady, const Duration(minutes: 75));
      expect(again.arrivalToSleep, const Duration(hours: 2, minutes: 45));
      expect(
        prefs.getInt(UserSettingsStore.arrivalToSleepKey),
        165,
      );
    });

    testWidgets('three arrival rows and sum at 360dp without overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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

      expect(find.byKey(const ValueKey('settings-arrival-deboard')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-hotel-transfer')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-after-hotel')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-arrival-to-sleep')), findsOneWidget);
      expect(find.text('하기·입국'), findsOneWidget);
      expect(find.text('호텔 이동'), findsOneWidget);
      expect(find.text('호텔 도착 후 준비'), findsOneWidget);
      expect(
        find.textContaining('램프 도착부터 잠들기까지 합계'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('arrival meal/sleep order', () {
    test('a) gap under 2h: auto/restFirst snack+wake meal, mealFirst early meal', () {
      final schedule = _sfoSample();
      final mealReady = UserSettings.defaults.hotelArrivalUtc(schedule.staUtc);
      // First sleep is 20:30Z; hotel arrival 19:05Z → gap under kMealLead.

      for (final order in [ArrivalOrder.auto, ArrivalOrder.restFirst]) {
        final events = _blocks(
          schedule,
          settings: UserSettings.defaults.copyWith(arrivalOrder: order),
        );
        final firstSleep = _sleeps(events).first;
        expect(firstSleep.startUtc, DateTime.utc(2026, 11, 29, 20, 30));

        expect(
          events.where(
            (e) =>
                e.kind == GuideEventKind.meal &&
                e.title == '식사' &&
                e.detail == '잠들기 전 식사.' &&
                e.startUtc.isBefore(firstSleep.startUtc),
          ),
          isEmpty,
        );
        final snack = events.singleWhere(
          (e) => e.kind == GuideEventKind.meal && e.title == '간식',
        );
        expect(snack.startUtc, mealReady);
        expect(snack.startUtc, DateTime.utc(2026, 11, 29, 19, 5));
        expect(snack.detail, contains('일어난 뒤에'));
        final wakeMeal = events.singleWhere(
          (e) =>
              e.kind == GuideEventKind.meal &&
              e.title == '식사' &&
              e.detail == '일어난 뒤 먹어요.',
        );
        expect(wakeMeal.startUtc, firstSleep.endUtc);
      }

      final mealFirst = _blocks(
        schedule,
        settings: UserSettings.defaults.copyWith(
          arrivalOrder: ArrivalOrder.mealFirst,
        ),
      );
      final sleep = _sleeps(mealFirst).first;
      final early = mealFirst.singleWhere(
        (e) =>
            e.kind == GuideEventKind.meal &&
            e.detail == '가볍게 먹고 바로 쉬어요.',
      );
      expect(early.startUtc, mealReady);
      expect(early.title, '식사');
      expect(mealFirst.where((e) => e.title == '간식'), isEmpty);
      expect(
        mealFirst.where((e) => e.detail == '일어난 뒤 먹어요.'),
        isEmpty,
      );
      expect(sleep.startUtc, DateTime.utc(2026, 11, 29, 20, 30));
    });

    test('b) gap at least 2h: auto/mealFirst pre-sleep meal, restFirst wake meal', () {
      // STA 08:00Z, hotel 09:30Z, night sleep 14:00–19:00Z → gap 4.5h.
      final schedule = _seoulDayArrival();
      final firstStart = DateTime.utc(2026, 11, 30, 14);
      final mealReady = UserSettings.defaults.hotelArrivalUtc(schedule.staUtc);

      for (final order in [ArrivalOrder.auto, ArrivalOrder.mealFirst]) {
        final events = _blocks(
          schedule,
          settings: UserSettings(
            defaultBedTime: const DayTime(hour: 23, minute: 0),
            defaultWakeTime: const DayTime(hour: 4, minute: 0),
            chosenSleep: const Duration(hours: 4),
            arrivalOrder: order,
          ),
        );
        final first = _sleeps(events).first;
        expect(first.startUtc, firstStart);
        final dinner = events.singleWhere(
          (e) =>
              e.kind == GuideEventKind.meal &&
              e.detail == '잠들기 전 식사.' &&
              e.startUtc.isAtSameMomentAs(firstStart.subtract(kMealLead)),
        );
        expect(dinner.startUtc, DateTime.utc(2026, 11, 30, 12));
      }

      final rest = _blocks(
        schedule,
        settings: const UserSettings(
          defaultBedTime: DayTime(hour: 23, minute: 0),
          defaultWakeTime: DayTime(hour: 4, minute: 0),
          chosenSleep: Duration(hours: 4),
          arrivalOrder: ArrivalOrder.restFirst,
        ),
      );
      final first = _sleeps(rest).first;
      expect(first.startUtc, firstStart);
      expect(
        rest.where((e) => e.detail == '잠들기 전 식사.'),
        isEmpty,
      );
      expect(
        rest.singleWhere((e) => e.title == '간식').startUtc,
        mealReady,
      );
      expect(mealReady, DateTime.utc(2026, 11, 30, 9, 30));
      expect(
        rest.singleWhere((e) => e.detail == '일어난 뒤 먹어요.').startUtc,
        first.endUtc,
      );
    });

    test('overnight 08:00 KST: hotel 09:30 snack, nap 10:30–13:30, wake meal', () {
      final schedule = _overnightArriveDay();
      final outbound = _overnightOutbound(schedule);
      final events = buildGuideEvents(
        schedule,
        outbound: outbound,
        settings: UserSettings.defaults,
      );
      final hotel = UserSettings.defaults.hotelArrivalUtc(schedule.staUtc);
      expect(hotel, schedule.staUtc.add(const Duration(minutes: 90)));

      final snack = events.singleWhere(
        (e) => e.kind == GuideEventKind.meal && e.title == '간식',
      );
      expect(snack.startUtc, hotel);

      final ready = schedule.staUtc.add(UserSettings.defaults.arrivalToSleep);
      final nap = _sleeps(events).singleWhere(
        (e) =>
            e.startUtc.isAtSameMomentAs(ready) &&
            e.detail.contains('밤샘 비행 뒤 짧은 낮잠'),
      );
      expect(nap.startUtc, ready);
      expect(
        nap.endUtc!.difference(nap.startUtc),
        const Duration(hours: 3),
      );
      expect(
        events.singleWhere((e) => e.detail == '일어난 뒤 먹어요.').startUtc,
        nap.endUtc,
      );
    });

    test('day 17:00 arrival: hotel 18:30, 21:00 pre-sleep meal, no overnight nap', () {
      final schedule = _seoulEveningArrival();
      final events = _blocks(schedule);
      final hotel = UserSettings.defaults.hotelArrivalUtc(schedule.staUtc);
      expect(hotel, DateTime.utc(2026, 11, 30, 9, 30)); // 17:00 KST + 90m → 18:30 KST = 09:30Z

      final night = _sleeps(events).firstWhere(
        (e) => e.startUtc.isAtSameMomentAs(DateTime.utc(2026, 11, 30, 14)), // 23:00 KST
      );
      expect(
        events.where((e) => e.detail.contains('밤샘 비행 뒤')),
        isEmpty,
      );
      final dinner = events.singleWhere(
        (e) =>
            e.kind == GuideEventKind.meal &&
            e.detail == '잠들기 전 식사.' &&
            e.startUtc.isAtSameMomentAs(night.startUtc.subtract(kMealLead)),
      );
      expect(dinner.startUtc, DateTime.utc(2026, 11, 30, 12)); // 21:00 KST
      // gap hotel→night = 4h30 ≥ kMealLead, so no arrival snack path.
      expect(events.where((e) => e.title == '간식'), isEmpty);
    });
  });

  group('overnight nap', () {
    test('c) overnight daytime arrival adds nap ≤3h; day flight and null do not', () {
      final schedule = _overnightArriveDay();
      final outbound = _overnightOutbound(schedule);
      final withNap = buildGuideEvents(
        schedule,
        outbound: outbound,
        settings: UserSettings.defaults,
      );
      final ready = schedule.staUtc.add(UserSettings.defaults.arrivalToSleep);
      final naps = _sleeps(withNap).where(
        (e) =>
            e.startUtc.isAtSameMomentAs(ready) &&
            e.detail.contains('밤샘 비행 뒤 짧은 낮잠'),
      );
      expect(naps, hasLength(1));
      final nap = naps.single;
      final length = nap.endUtc!.difference(nap.startUtc);
      expect(length.inMinutes % kSleepCycle.inMinutes, 0);
      expect(length, lessThanOrEqualTo(const Duration(hours: 3)));
      expect(length.inMinutes, lessThanOrEqualTo(kNapMaxCycles * 90));

      final nightStart = _sleeps(withNap)
          .where((e) => e.startUtc.isAfter(nap.endUtc!))
          .map((e) => e.startUtc)
          .fold<DateTime?>(null, (best, start) {
            if (best == null || start.isBefore(best)) return start;
            return best;
          });
      if (nightStart != null) {
        expect(
          nap.endUtc!.isAfter(nightStart.subtract(kNapGapBeforeNight)),
          isFalse,
        );
      }

      final dayFlight = buildGuideEvents(
        schedule,
        outbound: FlightLeg(
          flightNumber: 'XX000',
          origin: 'ICN',
          destination: 'LAX',
          originTimeZone: 'Asia/Seoul',
          destinationTimeZone: 'America/Los_Angeles',
          // Short daytime hop: little overlap with the mode night.
          std: schedule.staUtc.subtract(const Duration(hours: 2)),
          sta: schedule.staUtc,
        ),
      );
      expect(
        _sleeps(dayFlight).where((e) => e.detail.contains('밤샘 비행 뒤')),
        isEmpty,
      );

      final noOutbound = buildGuideEvents(
        schedule,
        lifestyle: JetlagLifestyle.kstAnchor,
      );
      expect(
        _sleeps(noOutbound).where((e) => e.detail.contains('밤샘 비행 뒤')),
        isEmpty,
      );
    });

    test('d) first-sleep nap path: 1 cycle unless overnight then up to 2', () {
      final schedule = _shortDayLayover();
      final one = lifestyleBlocks(
        schedule: schedule,
        lifestyle: JetlagLifestyle.kstAnchor,
      );
      final ready = schedule.staUtc.add(UserSettings.defaults.arrivalToSleep);
      final nap = _sleeps(one).where((e) => e.startUtc.isAtSameMomentAs(ready));
      expect(nap, hasLength(1));
      expect(
        nap.single.endUtc!.difference(nap.single.startUtc),
        kSleepCycle,
      );

      final outbound = FlightLeg(
        flightNumber: 'XX000',
        origin: 'ICN',
        destination: 'AMS',
        originTimeZone: 'Asia/Seoul',
        destinationTimeZone: 'Europe/Amsterdam',
        // Long enough to overlap the home night by ≥ kOvernightFlightMin.
        std: schedule.staUtc.subtract(const Duration(hours: 14)),
        sta: schedule.staUtc,
      );
      final two = lifestyleBlocks(
        schedule: schedule,
        lifestyle: JetlagLifestyle.kstAnchor,
        inboundStdUtc: outbound.stdUtc,
      );
      final overnightNap = _sleeps(two).where((e) => e.startUtc.isAtSameMomentAs(ready));
      expect(overnightNap, hasLength(1));
      final len = overnightNap.single.endUtc!.difference(
        overnightNap.single.startUtc,
      );
      expect(len.inMinutes % 90, 0);
      expect(len, greaterThanOrEqualTo(kSleepCycle));
      expect(len, lessThanOrEqualTo(const Duration(hours: 3)));
      expect(overnightNap.single.detail, contains('밤샘 비행 뒤'));
    });
  });

  group('westbound evening note', () {
    test('e) appends only for kstAnchor evening westbound', () {
      final phrase =
          '저녁에 서쪽으로 떠나는 편이에요. 한국시간을 그대로 두는 날이라 출발 전 수면이 특히 중요해요.';
      final westEvening = _laxEveningDeparture();
      final kst = _sleeps(_blocks(westEvening));
      final last = kst.lastWhere((e) => e.endUtc!.isBefore(westEvening.stdUtc));
      expect(last.detail.contains(phrase), isTrue);
      final start = last.startUtc;
      final end = last.endUtc;

      for (final lifestyle in [
        JetlagLifestyle.hybrid,
        JetlagLifestyle.localAdapt,
      ]) {
        final sleeps = _sleeps(_blocks(westEvening, lifestyle: lifestyle));
        expect(
          sleeps.any((e) => e.detail.contains('서쪽으로 떠나는')),
          isFalse,
        );
      }
      // Sleep instants for kstAnchor stay put when the note is appended.
      expect(last.startUtc, start);
      expect(last.endUtc, end);

      final dayDep = westEvening.copyWith(
        stdUtc: zonedUtc(
          iana: 'America/Los_Angeles',
          year: 2026,
          month: 12,
          day: 1,
          hour: 10,
          minute: 0,
        ),
      );
      expect(
        _sleeps(_blocks(dayDep)).any((e) => e.detail.contains('서쪽으로 떠나는')),
        isFalse,
      );

      final east = _amsEveningDeparture();
      expect(
        _sleeps(_blocks(east)).any((e) => e.detail.contains('서쪽으로 떠나는')),
        isFalse,
      );
    });
  });

  test('f) new copy avoids forbidden medical words', () {
    final texts = <String>[
      '가볍게 먹고 바로 쉬어요.',
      '배고프면 가볍게만 먹고 쉬어요. 식사는 일어난 뒤에 해요.',
      '일어난 뒤 먹어요.',
      '밤샘 비행 뒤 짧은 낮잠이에요. 밤 수면 전에 끝나게 잡았어요.',
      '저녁에 서쪽으로 떠나는 편이에요. 한국시간을 그대로 두는 날이라 출발 전 수면이 특히 중요해요.',
      '도착 후 식사와 수면 사이가 2시간보다 짧을 때 순서를 고릅니다.',
      '램프 도착부터 잠들기까지 합계 2시간 30분. 식사는 호텔 도착(하기+이동) 뒤에 둘 수 있어요.',
      '하기·입국',
      '호텔 이동',
      '호텔 도착 후 준비',
    ];
    const forbidden = ['권장', '치료', '처방', '진단', '효과'];
    final joined = texts.join('\n');
    for (final word in forbidden) {
      expect(joined.contains(word), isFalse, reason: word);
    }
  });
}

List<GuideEvent> _blocks(
  JetlagScheduleSnapshot schedule, {
  UserSettings settings = UserSettings.defaults,
  JetlagLifestyle lifestyle = JetlagLifestyle.kstAnchor,
  DateTime? inboundStdUtc,
}) {
  return lifestyleBlocks(
    schedule: schedule,
    settings: settings,
    lifestyle: lifestyle,
    inboundStdUtc: inboundStdUtc,
  );
}

List<GuideEvent> _sleeps(List<GuideEvent> events) {
  return events
      .where((e) => e.kind == GuideEventKind.sleep && e.endUtc != null)
      .toList()
    ..sort((a, b) => a.startUtc.compareTo(b.startUtc));
}

JetlagScheduleSnapshot _sfoSample() {
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

JetlagScheduleSnapshot _seoulDayArrival() {
  return JetlagScheduleSnapshot(
    stationLabel: 'SFO',
    localTimeZone: 'Asia/Seoul',
    referenceTimeZone: 'Asia/Seoul',
    staUtc: DateTime.utc(2026, 11, 30, 8),
    stdUtc: DateTime.utc(2026, 12, 1, 4, 20),
    pickupUtc: zonedUtc(
      iana: 'Asia/Seoul',
      year: 2026,
      month: 11,
      day: 30,
      hour: 18,
      minute: 45,
    ),
    flightNumber: 'XX000',
  );
}

/// 17:00 KST arrival; night sleep 23:00 → hotel 18:30, pre-sleep meal 21:00.
JetlagScheduleSnapshot _seoulEveningArrival() {
  final sta = zonedUtc(
    iana: 'Asia/Seoul',
    year: 2026,
    month: 11,
    day: 30,
    hour: 17,
    minute: 0,
  );
  return JetlagScheduleSnapshot(
    stationLabel: 'ICN',
    localTimeZone: 'Asia/Seoul',
    referenceTimeZone: 'Asia/Seoul',
    staUtc: sta,
    stdUtc: sta.add(const Duration(days: 2)),
    flightNumber: 'XX000',
  );
}

/// Arrive after the home wake so the mode clock reads daytime; inbound flight
/// overlaps the prior home night by more than [kOvernightFlightMin].
JetlagScheduleSnapshot _overnightArriveDay() {
  // 08:00 KST next calendar morning after a long inbound.
  final sta = zonedUtc(
    iana: 'Asia/Seoul',
    year: 2026,
    month: 11,
    day: 30,
    hour: 8,
    minute: 0,
  );
  return JetlagScheduleSnapshot(
    stationLabel: 'LAX',
    originLabel: 'ICN',
    localTimeZone: 'America/Los_Angeles',
    referenceTimeZone: 'Asia/Seoul',
    staUtc: sta,
    stdUtc: sta.add(const Duration(days: 2)),
    flightNumber: 'XX000',
  );
}

FlightLeg _overnightOutbound(JetlagScheduleSnapshot schedule) {
  return FlightLeg(
    flightNumber: 'XX000',
    origin: 'ICN',
    destination: 'LAX',
    originTimeZone: 'Asia/Seoul',
    destinationTimeZone: 'America/Los_Angeles',
    std: schedule.staUtc.subtract(const Duration(hours: 14)),
    sta: schedule.staUtc,
  );
}

/// Short daytime layover so mode nights do not fill; uses the first-sleep nap path.
///
/// Home bedtime is 23:00 KST (14:00Z). Arrival mid-afternoon KST leaves room for
/// one cycle before bed − kNapGapBeforeNight, and overnight can fit two.
JetlagScheduleSnapshot _shortDayLayover() {
  final sta = zonedUtc(
    iana: 'Europe/Amsterdam',
    year: 2026,
    month: 11,
    day: 28,
    hour: 6,
    minute: 30,
  );
  return JetlagScheduleSnapshot(
    stationLabel: 'AMS',
    originLabel: 'ICN',
    localTimeZone: 'Europe/Amsterdam',
    referenceTimeZone: 'Asia/Seoul',
    staUtc: sta,
    // Leaves before the next mode bedtime, so _sleepWindows stays empty.
    stdUtc: zonedUtc(
      iana: 'Europe/Amsterdam',
      year: 2026,
      month: 11,
      day: 28,
      hour: 14,
      minute: 0,
    ),
    flightNumber: 'XX001',
  );
}

JetlagScheduleSnapshot _laxEveningDeparture() {
  final sta = DateTime.utc(2026, 11, 29, 17, 35);
  final std = zonedUtc(
    iana: 'America/Los_Angeles',
    year: 2026,
    month: 12,
    day: 1,
    hour: 18,
    minute: 0,
  );
  return JetlagScheduleSnapshot(
    stationLabel: 'LAX',
    localTimeZone: 'America/Los_Angeles',
    referenceTimeZone: 'Asia/Seoul',
    staUtc: sta,
    stdUtc: std,
    pickupUtc: std.subtract(const Duration(hours: 3)),
    flightNumber: 'XX000',
  );
}

JetlagScheduleSnapshot _amsEveningDeparture() {
  final sta = _ams(27, 15, 0);
  final std = _ams(28, 19, 0);
  return JetlagScheduleSnapshot(
    stationLabel: 'AMS',
    originLabel: 'ICN',
    localTimeZone: 'Europe/Amsterdam',
    referenceTimeZone: 'Asia/Seoul',
    staUtc: sta,
    stdUtc: std,
    pickupUtc: _ams(28, 17, 0),
    flightNumber: 'XX001',
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
