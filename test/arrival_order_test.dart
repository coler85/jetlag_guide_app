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
    test('defaults to restFirst and copyWith/== work', () {
      expect(UserSettings.defaults.arrivalOrder, ArrivalOrder.restFirst);
      final meal = UserSettings.defaults.copyWith(
        arrivalOrder: ArrivalOrder.mealFirst,
      );
      expect(meal.arrivalOrder, ArrivalOrder.mealFirst);
      expect(meal == UserSettings.defaults, isFalse);
      expect(
        meal.copyWith(arrivalOrder: ArrivalOrder.restFirst),
        UserSettings.defaults,
      );
      expect(ArrivalOrder.fromName(null), ArrivalOrder.restFirst);
      expect(ArrivalOrder.fromName('nope'), ArrivalOrder.restFirst);
      expect(ArrivalOrder.fromName('auto'), ArrivalOrder.restFirst);
      expect(ArrivalOrder.fromName('restFirst'), ArrivalOrder.restFirst);
      expect(ArrivalOrder.fromName('mealFirst'), ArrivalOrder.mealFirst);
      expect(ArrivalOrder.restFirst.label, '휴식 먼저');
      expect(ArrivalOrder.mealFirst.label, '식사 먼저');
    });

    test('store saves, restores, and falls back unknown/auto to restFirst',
        () async {
      const store = UserSettingsStore();
      expect((await store.load()).arrivalOrder, ArrivalOrder.restFirst);

      await store.save(
        UserSettings.defaults.copyWith(arrivalOrder: ArrivalOrder.mealFirst),
      );
      expect((await store.load()).arrivalOrder, ArrivalOrder.mealFirst);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(UserSettingsStore.arrivalOrderKey, 'mystery');
      expect((await store.load()).arrivalOrder, ArrivalOrder.restFirst);

      await prefs.setString(UserSettingsStore.arrivalOrderKey, 'auto');
      expect((await store.load()).arrivalOrder, ArrivalOrder.restFirst);
    });
  });

  group('settings form arrival order', () {
    testWidgets('shows two choices at 360dp without overflow', (
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
      expect(
        find.byKey(const ValueKey('settings-arrival-order-auto')),
        findsNothing,
      );
      expect(find.text('휴식 먼저'), findsOneWidget);
      expect(find.text('식사 먼저'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('settings-arrival-order-meal')));
      await tester.pumpAndSettle();
      expect(settings.arrivalOrder, ArrivalOrder.mealFirst);

      await tester.tap(find.byKey(const ValueKey('settings-arrival-order-rest')));
      await tester.pumpAndSettle();
      expect(settings.arrivalOrder, ArrivalOrder.restFirst);
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
    test('a) mode-night arrival sleep: order ignored, no pre-hotel meal', () {
      final schedule = _sfoSample();
      final hotel = UserSettings.defaults.hotelArrivalUtc(schedule.staUtc);

      List<DateTime> mealStarts(List<GuideEvent> events) => events
          .where((e) => e.kind == GuideEventKind.meal)
          .map((e) => e.startUtc)
          .toList()
        ..sort();

      final rest = _blocks(
        schedule,
        settings: UserSettings.defaults.copyWith(
          arrivalOrder: ArrivalOrder.restFirst,
        ),
      );
      final meal = _blocks(
        schedule,
        settings: UserSettings.defaults.copyWith(
          arrivalOrder: ArrivalOrder.mealFirst,
        ),
      );
      final firstSleep = _sleeps(rest).first;
      expect(
        firstSleep.startUtc.isAtSameMomentAs(DateTime.utc(2026, 11, 29, 20, 30)),
        isTrue,
      );
      expect(mealStarts(rest), mealStarts(meal));
      expect(rest.where((e) => e.title == '간식'), isEmpty);
      expect(
        rest.where((e) => e.detail == '가볍게 먹고 바로 쉬어요.'),
        isEmpty,
      );
      expect(
        rest.where(
          (e) =>
              e.kind == GuideEventKind.meal &&
              e.startUtc.isBefore(hotel),
        ),
        isEmpty,
      );
      expect(
        rest.where((e) => e.detail == '잠들기 전 식사.'),
        isEmpty,
      );
    });

    test('overnight 08:00 KST: nap clash + hotel defer; both keep 13:30', () {
      final schedule = _overnightArriveDay();
      final outbound = _overnightOutbound(schedule);
      final hotel = UserSettings.defaults.hotelArrivalUtc(schedule.staUtc);
      expect(
        hotel.isAtSameMomentAs(schedule.staUtc.add(const Duration(minutes: 90))),
        isTrue,
      );
      expect(
        hotel.isAtSameMomentAs(DateTime.utc(2026, 11, 30, 0, 30)),
        isTrue,
      ); // 09:30 KST
      final ready = schedule.staUtc.add(UserSettings.defaults.arrivalToSleep);
      final nightBed = DateTime.utc(2026, 11, 30, 14); // 23:00 KST
      final deadline = nightBed.subtract(kMealLead); // 21:00 KST = 12:00Z
      final meal13 = DateTime.utc(2026, 11, 30, 4); // 13:00 KST
      final meal18 = DateTime.utc(2026, 11, 30, 9); // 18:00 KST
      final meal1330 = DateTime.utc(2026, 11, 30, 4, 30); // 13:30 KST

      final rest = buildGuideEvents(
        schedule,
        outbound: outbound,
        settings: UserSettings.defaults,
      );
      expect(
        rest.where(
          (e) =>
              e.kind == GuideEventKind.meal &&
              e.startUtc.isBefore(schedule.staUtc),
        ),
        isEmpty,
      );
      // 09:00 → hotel 09:30; 13:00 overlaps nap → 13:30; 18:00 stays.
      expect(
        rest
            .singleWhere(
              (e) =>
                  e.kind == GuideEventKind.meal &&
                  e.startUtc.isAtSameMomentAs(hotel) &&
                  e.detail == '식사.',
            )
            .startUtc
            .isAtSameMomentAs(hotel),
        isTrue,
      );
      expect(
        rest.where(
          (e) =>
              e.kind == GuideEventKind.meal &&
              e.startUtc.isAtSameMomentAs(meal13),
        ),
        isEmpty,
      );
      final nap = _sleeps(rest).singleWhere(
        (e) =>
            e.startUtc.isAtSameMomentAs(ready) &&
            e.detail.contains('밤샘 비행 뒤 짧은 낮잠'),
      );
      expect(
        nap.startUtc.isAtSameMomentAs(DateTime.utc(2026, 11, 30, 1, 30)),
        isTrue,
      ); // 10:30 KST
      expect(nap.endUtc!.isAtSameMomentAs(meal1330), isTrue);
      expect(
        rest
            .singleWhere(
              (e) =>
                  e.kind == GuideEventKind.meal &&
                  e.title == '식사' &&
                  e.startUtc.isAtSameMomentAs(meal1330),
            )
            .startUtc
            .isAtSameMomentAs(meal1330),
        isTrue,
      );
      expect(
        rest
            .singleWhere(
              (e) =>
                  e.kind == GuideEventKind.meal &&
                  e.startUtc.isAtSameMomentAs(meal18),
            )
            .startUtc
            .isAtSameMomentAs(meal18),
        isTrue,
      );
      expect(
        rest.where(
          (e) =>
              e.kind == GuideEventKind.meal &&
              e.startUtc.isAtSameMomentAs(deadline),
        ),
        isEmpty,
      );
      expect(
        rest
            .singleWhere(
              (e) =>
                  e.kind == GuideEventKind.mealDeadline &&
                  e.startUtc.isAtSameMomentAs(deadline),
            )
            .title,
        '식사 마감',
      );
      expect(rest.where((e) => e.title == '간식'), isEmpty);
      expect(
        rest.where((e) => e.detail == '가볍게 먹고 바로 쉬어요.'),
        isEmpty,
      );
      final night = _sleeps(rest).singleWhere(
        (e) => e.startUtc.isAtSameMomentAs(nightBed),
      );
      expect(night.endUtc!.isAtSameMomentAs(DateTime.utc(2026, 11, 30, 22)), isTrue);

      final mealFirst = buildGuideEvents(
        schedule,
        outbound: outbound,
        settings: UserSettings.defaults.copyWith(
          arrivalOrder: ArrivalOrder.mealFirst,
        ),
      );
      expect(
        mealFirst.where(
          (e) =>
              e.kind == GuideEventKind.meal &&
              e.startUtc.isBefore(schedule.staUtc),
        ),
        isEmpty,
      );
      // 09:00 defer + light meal merge at 09:30; 13:00 → 13:30 kept.
      final light = mealFirst.singleWhere(
        (e) =>
            e.kind == GuideEventKind.meal &&
            e.detail == '가볍게 먹고 바로 쉬어요.',
      );
      expect(light.title, '식사');
      expect(light.startUtc.isAtSameMomentAs(hotel), isTrue);
      expect(
        mealFirst.where(
          (e) =>
              e.kind == GuideEventKind.meal &&
              e.startUtc.isAtSameMomentAs(hotel),
        ),
        hasLength(1),
      );
      expect(
        mealFirst.where(
          (e) =>
              e.kind == GuideEventKind.meal &&
              e.startUtc.isAtSameMomentAs(meal13),
        ),
        isEmpty,
      );
      expect(
        mealFirst
            .singleWhere(
              (e) =>
                  e.kind == GuideEventKind.meal &&
                  e.title == '식사' &&
                  e.detail == '식사.' &&
                  e.startUtc.isAtSameMomentAs(meal1330),
            )
            .startUtc
            .isAtSameMomentAs(meal1330),
        isTrue,
      );
      expect(
        mealFirst
            .singleWhere(
              (e) =>
                  e.kind == GuideEventKind.meal &&
                  e.startUtc.isAtSameMomentAs(meal18),
            )
            .startUtc
            .isAtSameMomentAs(meal18),
        isTrue,
      );
      expect(
        mealFirst
            .singleWhere(
              (e) =>
                  e.kind == GuideEventKind.mealDeadline &&
                  e.startUtc.isAtSameMomentAs(deadline),
            )
            .startUtc
            .isAtSameMomentAs(deadline),
        isTrue,
      );
      expect(
        mealFirst.where(
          (e) =>
              e.kind == GuideEventKind.meal &&
              e.startUtc.isAtSameMomentAs(deadline),
        ),
        isEmpty,
      );
      expect(mealFirst.where((e) => e.title == '간식'), isEmpty);
    });

    test('day 17:00 arrival: both orders defer 18:00 dinner to hotel 18:30', () {
      final schedule = _seoulEveningArrival();
      final hotel = UserSettings.defaults.hotelArrivalUtc(schedule.staUtc);
      expect(
        hotel.isAtSameMomentAs(DateTime.utc(2026, 11, 30, 9, 30)),
        isTrue,
      ); // 18:30 KST
      final nightBed = DateTime.utc(2026, 11, 30, 14); // 23:00 KST
      final deadline = nightBed.subtract(kMealLead); // 21:00 KST
      final nextMorning = DateTime.utc(2026, 11, 30, 22); // 07:00 KST Dec 1
      final day2Meal09 = DateTime.utc(2026, 12, 1, 0); // 09:00 KST
      final day2Meal13 = DateTime.utc(2026, 12, 1, 4); // 13:00 KST
      final day2Meal18 = DateTime.utc(2026, 12, 1, 9); // 18:00 KST

      List<String> mealFingerprint(List<GuideEvent> events) => events
          .where((e) => e.kind == GuideEventKind.meal)
          .map((e) => '${e.startUtc.toIso8601String()}|${e.title}|${e.detail}')
          .toList()
        ..sort();

      List<String>? shared;
      for (final order in ArrivalOrder.values) {
        final events = _blocks(
          schedule,
          settings: UserSettings.defaults.copyWith(arrivalOrder: order),
        );
        final night = _sleeps(events).firstWhere(
          (e) => e.startUtc.isAtSameMomentAs(nightBed),
        );
        expect(
          night.endUtc!.isAtSameMomentAs(nextMorning),
          isTrue,
        );
        expect(
          events.where((e) => e.detail.contains('밤샘 비행 뒤')),
          isEmpty,
        );
        expect(
          events.where(
            (e) =>
                e.kind == GuideEventKind.meal &&
                e.startUtc.isBefore(hotel),
          ),
          isEmpty,
        );
        // 18:00 KST (+30m ≤ 1h) → hotel 18:30 dinner.
        expect(
          events
              .singleWhere(
                (e) =>
                    e.kind == GuideEventKind.meal &&
                    e.title == '식사' &&
                    e.startUtc.isAtSameMomentAs(hotel),
              )
              .startUtc
              .isAtSameMomentAs(hotel),
          isTrue,
        );
        expect(
          events.where(
            (e) =>
                e.kind == GuideEventKind.meal &&
                e.startUtc.isAtSameMomentAs(DateTime.utc(2026, 11, 30, 9)),
          ),
          isEmpty,
        ); // original 18:00 gone
        expect(
          events.where((e) => e.title == '간식'),
          isEmpty,
        );
        expect(
          events
              .singleWhere(
                (e) =>
                    e.kind == GuideEventKind.mealDeadline &&
                    e.startUtc.isAtSameMomentAs(deadline),
              )
              .startUtc
              .isAtSameMomentAs(deadline),
          isTrue,
        );
        expect(
          events.where(
            (e) =>
                e.kind == GuideEventKind.meal &&
                e.startUtc.isAtSameMomentAs(deadline),
          ),
          isEmpty,
        );
        for (final at in [day2Meal09, day2Meal13, day2Meal18]) {
          expect(
            events.any(
              (e) =>
                  e.kind == GuideEventKind.meal &&
                  e.startUtc.isAtSameMomentAs(at),
            ),
            isTrue,
            reason: at.toIso8601String(),
          );
        }
        shared ??= mealFingerprint(events);
        expect(mealFingerprint(events), shared);
      }
    });

    test('night 21:00 KST arrival: both orders same; deadline after hotel', () {
      final schedule = _seoulLateNightArrival();
      final hotel = UserSettings.defaults.hotelArrivalUtc(schedule.staUtc);
      expect(
        hotel.isAtSameMomentAs(DateTime.utc(2026, 11, 30, 13, 30)),
        isTrue,
      ); // 22:30 KST
      final ready = schedule.staUtc.add(UserSettings.defaults.arrivalToSleep);
      expect(
        ready.isAtSameMomentAs(DateTime.utc(2026, 11, 30, 14, 30)),
        isTrue,
      ); // 23:30 KST earliest start
      final firstBed = DateTime.utc(2026, 11, 30, 16); // 01:00 KST
      final deadline = firstBed.subtract(kMealLead); // 23:00 KST = 14:00Z
      final day2Meal09 = DateTime.utc(2026, 12, 1, 0);
      final day2Meal13 = DateTime.utc(2026, 12, 1, 4);
      final day2Meal18 = DateTime.utc(2026, 12, 1, 9);

      List<String> mealFingerprint(List<GuideEvent> events) => events
          .where((e) => e.kind == GuideEventKind.meal)
          .map((e) => '${e.startUtc.toIso8601String()}|${e.title}|${e.detail}')
          .toList()
        ..sort();

      List<String>? shared;
      for (final order in ArrivalOrder.values) {
        final events = buildGuideEvents(
          schedule,
          settings: UserSettings.defaults.copyWith(arrivalOrder: order),
        );
        expect(
          events.where(
            (e) =>
                e.kind == GuideEventKind.meal &&
                e.startUtc.isBefore(schedule.staUtc),
          ),
          isEmpty,
        );
        final first = _sleeps(events).first;
        expect(first.startUtc.isAtSameMomentAs(firstBed), isTrue);
        expect(
          first.endUtc!.isAtSameMomentAs(DateTime.utc(2026, 11, 30, 22)),
          isTrue,
        ); // 07:00 KST
        expect(!first.startUtc.isBefore(ready), isTrue);
        expect(
          events.where((e) => e.detail.contains('밤샘 비행 뒤')),
          isEmpty,
        );
        expect(events.where((e) => e.title == '간식'), isEmpty);
        // Arrival-day 18:00 is still in transit.
        expect(
          events.where(
            (e) =>
                e.kind == GuideEventKind.meal &&
                e.startUtc.isAtSameMomentAs(DateTime.utc(2026, 11, 30, 9)),
          ),
          isEmpty,
        );
        expect(
          events
              .singleWhere(
                (e) =>
                    e.kind == GuideEventKind.mealDeadline &&
                    e.startUtc.isAtSameMomentAs(deadline),
              )
              .startUtc
              .isAtSameMomentAs(deadline),
          isTrue,
        );
        expect(
          events.where(
            (e) =>
                e.kind == GuideEventKind.meal && e.startUtc.isBefore(hotel),
          ),
          isEmpty,
        );
        for (final at in [day2Meal09, day2Meal13, day2Meal18]) {
          expect(
            events.any(
              (e) =>
                  e.kind == GuideEventKind.meal &&
                  e.startUtc.isAtSameMomentAs(at),
            ),
            isTrue,
            reason: at.toIso8601String(),
          );
        }
        shared ??= mealFingerprint(events);
        expect(mealFingerprint(events), shared);
      }
    });

    test('mid-stay day keeps 09/13/18 and omits meals after deadline', () {
      final schedule = _seoulEveningArrival();
      final events = _blocks(schedule);
      final day2 = DateTime.utc(2026, 12, 1);
      final meals = events
          .where(
            (e) =>
                e.kind == GuideEventKind.meal &&
                !e.startUtc.isBefore(day2) &&
                e.startUtc.isBefore(day2.add(const Duration(days: 1))),
          )
          .map((e) => e.startUtc)
          .toList()
        ..sort();
      expect(meals, hasLength(3));
      expect(meals[0].isAtSameMomentAs(DateTime.utc(2026, 12, 1, 0)), isTrue);
      expect(meals[1].isAtSameMomentAs(DateTime.utc(2026, 12, 1, 4)), isTrue);
      expect(meals[2].isAtSameMomentAs(DateTime.utc(2026, 12, 1, 9)), isTrue);
      final night = _sleeps(events).firstWhere(
        (e) => e.startUtc.isAtSameMomentAs(DateTime.utc(2026, 12, 1, 14)),
      );
      final deadline = night.startUtc.subtract(kMealLead);
      expect(
        events.any(
          (e) =>
              e.kind == GuideEventKind.mealDeadline &&
              e.startUtc.isAtSameMomentAs(deadline),
        ),
        isTrue,
      );
      expect(
        events.where(
          (e) =>
              e.kind == GuideEventKind.meal &&
              !e.startUtc.isBefore(deadline) &&
              e.startUtc.isBefore(night.startUtc),
        ),
        isEmpty,
      );
    });

    test('departure pull: lunch 13:00 → pickup 12:00; 10:00 omits', () {
      final stay = _seoulEveningArrival();
      final lunch = DateTime.utc(2026, 12, 1, 4); // 13:00 KST
      final pullOk = DateTime.utc(2026, 12, 1, 3); // 12:00 KST
      final pullFar = DateTime.utc(2026, 12, 1, 1); // 10:00 KST

      final pulled = _blocks(
        stay.copyWith(pickupUtc: pullOk, stdUtc: pullOk.add(const Duration(hours: 4))),
      );
      expect(
        pulled
            .singleWhere(
              (e) =>
                  e.kind == GuideEventKind.meal &&
                  e.startUtc.isAtSameMomentAs(pullOk),
            )
            .startUtc
            .isAtSameMomentAs(pullOk),
        isTrue,
      );
      expect(
        pulled.where(
          (e) =>
              e.kind == GuideEventKind.meal &&
              e.startUtc.isAtSameMomentAs(lunch),
        ),
        isEmpty,
      );

      final omitted = _blocks(
        stay.copyWith(
          pickupUtc: pullFar,
          stdUtc: pullFar.add(const Duration(hours: 4)),
        ),
      );
      expect(
        omitted.where(
          (e) =>
              e.kind == GuideEventKind.meal &&
              (e.startUtc.isAtSameMomentAs(lunch) ||
                  e.startUtc.isAtSameMomentAs(pullFar)),
        ),
        isEmpty,
      );
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
      '이 시각 이후 식사는 두지 않습니다.',
      '식사 마감',
      '밤샘 비행 뒤 짧은 낮잠이에요. 밤 수면 전에 끝나게 잡았어요.',
      '저녁에 서쪽으로 떠나는 편이에요. 한국시간을 그대로 두는 날이라 출발 전 수면이 특히 중요해요.',
      '휴식 먼저가 기본입니다. 도착 후 낮잠과 기본 식사 시각(09·13·18)이 '
          '겹칠 때만 이 순서를 씁니다. 식사 먼저는 호텔 도착에 가벼운 식사를 '
          '더하고 겹친 끼니는 낮잠 뒤로 미룹니다. 휴식 먼저는 겹친 끼니만 '
          '낮잠 뒤로 미룹니다(각 ±1시간). 호텔 도착 전·출발 후 끼니도 같은 '
          '폭 안에서 호텔 도착·출발로 옮기고, 폭을 넘으면 생략합니다. '
          '잠들기 2시간 전은 끼니가 아니라 식사 마감선입니다.',
      '식사는 모드 시계 09:00·13:00·18:00에 호텔에 있으면 두고, '
          '호텔 도착 전·출발 후는 ±1시간 안에서만 옮기며 폭을 넘으면 생략해요. '
          '잠들기 2시간 전은 식사 마감선입니다.',
      '하기·입국',
      '호텔 이동',
      '호텔 도착 후 준비',
      '휴식 먼저',
      '식사 먼저',
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

/// 17:00 KST arrival; night sleep 23:00 → hotel 18:30, meal deadline 21:00.
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

/// 21:00 KST ramp arrival; hotel 22:30. Earliest sleep 23:30, but default\n/// 7h target packs 4 cycles ending at 07:00, so first night is 01:00–07:00.
JetlagScheduleSnapshot _seoulLateNightArrival() {
  final sta = zonedUtc(
    iana: 'Asia/Seoul',
    year: 2026,
    month: 11,
    day: 30,
    hour: 21,
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
