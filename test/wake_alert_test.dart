import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:jetlag_guide_app/main.dart';
import 'package:jetlag_guide_app/models/flight_schedule_input.dart';
import 'package:jetlag_guide_app/models/guide_event.dart';
import 'package:jetlag_guide_app/models/user_settings.dart';
import 'package:jetlag_guide_app/notifications/clock_alarm_launcher.dart';
import 'package:jetlag_guide_app/notifications/clock_alarm_plan.dart';
import 'package:jetlag_guide_app/notifications/guide_alert_plan.dart';
import 'package:jetlag_guide_app/notifications/jetlag_alert_channel.dart';
import 'package:jetlag_guide_app/notifications/jetlag_alert_scheduler.dart';
import 'package:jetlag_guide_app/state/jetlag_guide_controller.dart';
import 'package:jetlag_guide_app/state/jetlag_log_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ensureJetlagTimeZones();
  });

  group('guide alert planners', () {
    test('caffeine/meal/bed skip past, cap at 12, keep copy clean', () {
      final now = DateTime.utc(2026, 11, 27, 12);
      final events = <GuideEvent>[
        GuideEvent(
          id: 'caf-past',
          kind: GuideEventKind.caffeine,
          startUtc: DateTime.utc(2026, 11, 27, 10),
          title: '카페인',
          detail: '과거',
        ),
        GuideEvent(
          id: 'meal-deadline',
          kind: GuideEventKind.mealDeadline,
          startUtc: DateTime.utc(2026, 11, 28, 8),
          title: '식사 마감',
          detail: '제외',
        ),
        GuideEvent(
          id: 'meal-a',
          kind: GuideEventKind.meal,
          startUtc: DateTime.utc(2026, 11, 28, 9),
          title: '식사',
          detail: '아침',
        ),
        GuideEvent(
          id: 'caf-a',
          kind: GuideEventKind.caffeine,
          startUtc: DateTime.utc(2026, 11, 28, 14),
          title: '카페인',
          detail: '컷',
        ),
        GuideEvent(
          id: 'sleep-soon',
          kind: GuideEventKind.sleep,
          startUtc: DateTime.utc(2026, 11, 27, 22),
          endUtc: DateTime.utc(2026, 11, 28, 6),
          title: '수면',
          detail: '곧',
        ),
        GuideEvent(
          id: 'sleep-near',
          kind: GuideEventKind.sleep,
          startUtc: now.add(const Duration(minutes: 20)),
          endUtc: now.add(const Duration(hours: 8)),
          title: '수면',
          detail: '30분 안',
        ),
        for (var i = 0; i < 14; i++) ...[
          GuideEvent(
            id: 'caf-$i',
            kind: GuideEventKind.caffeine,
            startUtc: DateTime.utc(2026, 12, 1 + i, 14),
            title: '카페인',
            detail: '여분',
          ),
          GuideEvent(
            id: 'meal-$i',
            kind: GuideEventKind.meal,
            startUtc: DateTime.utc(2026, 12, 1 + i, 12),
            title: '식사',
            detail: '여분',
          ),
          GuideEvent(
            id: 'sleep-$i',
            kind: GuideEventKind.sleep,
            startUtc: DateTime.utc(2026, 12, 1 + i, 22),
            endUtc: DateTime.utc(2026, 12, 2 + i, 6),
            title: '수면',
            detail: '여분',
          ),
        ],
      ];

      final caffeine = planCaffeineAlerts(
        events: events,
        nowUtc: now,
        localIana: 'Europe/Amsterdam',
        homeIana: 'Asia/Seoul',
      );
      final meals = planMealAlerts(
        events: events,
        nowUtc: now,
        localIana: 'Europe/Amsterdam',
        homeIana: 'Asia/Seoul',
      );
      final beds = planBedAlerts(
        events: events,
        nowUtc: now,
        localIana: 'Europe/Amsterdam',
        homeIana: 'Asia/Seoul',
      );

      expect(caffeine, hasLength(12));
      expect(meals, hasLength(12));
      expect(beds, hasLength(12));
      expect(caffeine.first.id, JetlagAlertChannel.caffeineIdStart);
      expect(meals.first.id, JetlagAlertChannel.mealIdStart);
      expect(beds.first.id, JetlagAlertChannel.bedIdStart);
      expect(
        caffeine.last.id,
        JetlagAlertChannel.caffeineIdStart +
            JetlagAlertChannel.guideMaxCount -
            1,
      );

      expect(
        caffeine.first.whenUtc.isAtSameMomentAs(DateTime.utc(2026, 11, 28, 14)),
        isTrue,
      );
      expect(
        meals.first.whenUtc.isAtSameMomentAs(DateTime.utc(2026, 11, 28, 9)),
        isTrue,
      );
      expect(meals.any((a) => a.title.contains('식사 마감')), isFalse);

      final bed = beds.first;
      expect(
        bed.whenUtc.isAtSameMomentAs(DateTime.utc(2026, 11, 27, 21, 30)),
        isTrue,
      );
      expect(bed.title, startsWith('곧 취침 '));
      expect(
        bed.title,
        contains(formatHm(DateTime.utc(2026, 11, 27, 22), 'Europe/Amsterdam')),
      );
      expect(bed.body, '곧 취침이에요');
      expect(
        beds.any(
          (a) => a.whenUtc.isAtSameMomentAs(
            now
                .add(const Duration(minutes: 20))
                .subtract(const Duration(minutes: 30)),
          ),
        ),
        isFalse,
      );

      expect(caffeine.first.body, '카페인 마감 시각이에요');
      expect(meals.first.body, '식사 시간이에요');
      expect(caffeine.first.title, startsWith('카페인 마감 '));
      expect(meals.first.title, startsWith('식사 '));
      for (final alert in caffeine) {
        expect(alert.title, contains('홈'));
        expect(
          alert.title,
          contains(formatHm(alert.whenUtc, 'Europe/Amsterdam')),
        );
        expect(alert.title, contains(formatHm(alert.whenUtc, 'Asia/Seoul')));
        expect(
          alert.title,
          contains(zoneAbbreviation(alert.whenUtc, 'Asia/Seoul')),
        );
      }
      final bedTime = DateTime.utc(2026, 11, 27, 22);
      expect(bed.title, contains(formatHm(bedTime, 'Europe/Amsterdam')));
      expect(bed.title, contains(formatHm(bedTime, 'Asia/Seoul')));
      expect(bed.title, contains(zoneAbbreviation(bedTime, 'Asia/Seoul')));

      final joined = [
        ...caffeine,
        ...meals,
        ...beds,
      ].map((a) => '${a.title}\n${a.body}').join('\n');
      for (final word in [
        '권장',
        '치료',
        '처방',
        '진단',
        '효과',
        'XX000',
        'XX001',
        'AMS',
        'ICN',
        'KE',
      ]) {
        expect(joined.contains(word), isFalse, reason: word);
      }
    });

    test('push titles use IANA DST: AMS winter UTC+1, summer UTC+2', () {
      final winterBed = zonedUtc(
        iana: 'Europe/Amsterdam',
        year: 2026,
        month: 11,
        day: 28,
        hour: 22,
        minute: 0,
      );
      final winterCaffeine = zonedUtc(
        iana: 'Europe/Amsterdam',
        year: 2026,
        month: 11,
        day: 28,
        hour: 15,
        minute: 0,
      );
      final winterMeal = zonedUtc(
        iana: 'Europe/Amsterdam',
        year: 2026,
        month: 11,
        day: 28,
        hour: 13,
        minute: 0,
      );
      // Fire times must be in the future relative to now.
      final now = DateTime.utc(2026, 11, 28, 8);
      final beds = planBedAlerts(
        events: [
          GuideEvent(
            id: 'sleep-winter',
            kind: GuideEventKind.sleep,
            startUtc: winterBed,
            endUtc: winterBed.add(const Duration(hours: 7)),
            title: '수면',
            detail: '밤',
          ),
        ],
        nowUtc: now,
        localIana: 'Europe/Amsterdam',
        homeIana: 'Asia/Seoul',
      );
      expect(beds, hasLength(1));
      expect(beds.single.title, '곧 취침 22:00 · 홈 06:00 KST');
      expect(
        beds.single.whenUtc.isAtSameMomentAs(
          winterBed.subtract(const Duration(minutes: 30)),
        ),
        isTrue,
      );

      final caffeines = planCaffeineAlerts(
        events: [
          GuideEvent(
            id: 'caf-winter',
            kind: GuideEventKind.caffeine,
            startUtc: winterCaffeine,
            title: '카페인 마감',
            detail: '컷오프',
          ),
        ],
        nowUtc: now,
        localIana: 'Europe/Amsterdam',
        homeIana: 'Asia/Seoul',
      );
      expect(caffeines.single.title, '카페인 마감 15:00 · 홈 23:00 KST');

      final meals = planMealAlerts(
        events: [
          GuideEvent(
            id: 'meal-winter',
            kind: GuideEventKind.meal,
            startUtc: winterMeal,
            title: '식사',
            detail: '식사.',
          ),
        ],
        nowUtc: now,
        localIana: 'Europe/Amsterdam',
        homeIana: 'Asia/Seoul',
      );
      expect(meals.single.title, '식사 13:00 · 홈 21:00 KST');

      final summerMealAt = zonedUtc(
        iana: 'Europe/Amsterdam',
        year: 2026,
        month: 7,
        day: 15,
        hour: 13,
        minute: 0,
      );
      final summerMeals = planMealAlerts(
        events: [
          GuideEvent(
            id: 'meal-summer',
            kind: GuideEventKind.meal,
            startUtc: summerMealAt,
            title: '식사',
            detail: '식사.',
          ),
        ],
        nowUtc: DateTime.utc(2026, 7, 15, 8),
        localIana: 'Europe/Amsterdam',
        homeIana: 'Asia/Seoul',
      );
      expect(summerMeals.single.title, '식사 13:00 · 홈 20:00 KST');
    });
  });

  group('clock alarm plan', () {
    test('24h active, 25h inactive, past not a target, wakeup = pickup-1h', () {
      final now = DateTime.utc(2026, 11, 27, 12);
      final events = <GuideEvent>[
        GuideEvent(
          id: 'past',
          kind: GuideEventKind.sleep,
          startUtc: DateTime.utc(2026, 11, 26, 22),
          endUtc: DateTime.utc(2026, 11, 27, 6),
          title: '수면',
          detail: '과거',
        ),
        GuideEvent(
          id: 'logged',
          kind: GuideEventKind.loggedSleep,
          startUtc: DateTime.utc(2026, 11, 28, 1),
          endUtc: DateTime.utc(2026, 11, 28, 8),
          title: '기록한 수면',
          detail: '기록',
        ),
        GuideEvent(
          id: 'in24',
          kind: GuideEventKind.sleep,
          startUtc: DateTime.utc(2026, 11, 27, 22),
          endUtc: now.add(const Duration(hours: 10)),
          title: '수면',
          detail: '안',
        ),
      ];

      final wake = planNextClockWake(events: events, nowUtc: now)!;
      expect(wake.active, isTrue);
      expect(wake.message, kClockAlarmWakeMessage);
      expect(
        wake.whenUtc.isAtSameMomentAs(now.add(const Duration(hours: 10))),
        isTrue,
      );

      final farEvents = [
        GuideEvent(
          id: 'far',
          kind: GuideEventKind.sleep,
          startUtc: DateTime.utc(2026, 11, 28, 22),
          endUtc: now.add(const Duration(hours: 25)),
          title: '수면',
          detail: '밖',
        ),
      ];
      final far = planNextClockWake(events: farEvents, nowUtc: now)!;
      expect(far.active, isFalse);

      expect(
        planNextClockWake(
          events: [
            GuideEvent(
              id: 'only-past',
              kind: GuideEventKind.sleep,
              startUtc: DateTime.utc(2026, 11, 26, 22),
              endUtc: DateTime.utc(2026, 11, 27, 6),
              title: '수면',
              detail: '과거',
            ),
          ],
          nowUtc: now,
        ),
        isNull,
      );

      final call = planNextWakeupCall(
        pickupUtc: now.add(const Duration(hours: 5)),
        nowUtc: now,
      )!;
      expect(
        call.whenUtc.isAtSameMomentAs(now.add(const Duration(hours: 4))),
        isTrue,
      );
      expect(call.message, kClockAlarmWakeupCallMessage);
      expect(call.active, isTrue);

      final farCall = planNextWakeupCall(
        pickupUtc: now.add(const Duration(hours: 26)),
        nowUtc: now,
      )!;
      expect(farCall.active, isFalse);

      expect(
        planNextWakeupCall(
          pickupUtc: now.add(const Duration(minutes: 30)),
          nowUtc: now,
        ),
        isNull,
      );
      expect(planNextWakeupCall(pickupUtc: null, nowUtc: now), isNull);

      expect(
        isClockAlarmWithinWindow(now.add(const Duration(hours: 24)), now),
        isTrue,
      );
      expect(
        isClockAlarmWithinWindow(
          now.add(const Duration(hours: 24, minutes: 1)),
          now,
        ),
        isFalse,
      );
    });

    test('device local strips TZDateTime so AMS winter is not one hour early', () {
      // 21:00 CET on 28 Nov 2026 = 20:00 UTC = 05:00 KST.
      // TZDateTime.toLocal() would wrongly keep 20:00 (tz.local is UTC).
      final wake = zonedUtc(
        iana: 'Europe/Amsterdam',
        year: 2026,
        month: 11,
        day: 28,
        hour: 21,
        minute: 0,
      );
      expect(formatHm(wake, 'Europe/Amsterdam'), '21:00');
      expect(formatHm(wake, 'Asia/Seoul'), '05:00');
      expect(wake.toUtc().hour, 20);

      final device = clockAlarmDeviceLocal(wake);
      final os = DateTime.fromMicrosecondsSinceEpoch(
        wake.toUtc().microsecondsSinceEpoch,
        isUtc: true,
      ).toLocal();
      expect(device.hour, os.hour);
      expect(device.minute, os.minute);
      expect(device.hour, isNot(20));
      expect(
        '${device.hour.toString().padLeft(2, '0')}:'
        '${device.minute.toString().padLeft(2, '0')}',
        formatHm(wake, 'Asia/Seoul'),
      );

      final summer = zonedUtc(
        iana: 'Europe/Amsterdam',
        year: 2026,
        month: 7,
        day: 15,
        hour: 21,
        minute: 0,
      );
      expect(formatHm(summer, 'Europe/Amsterdam'), '21:00');
      expect(formatHm(summer, 'Asia/Seoul'), '04:00');
      expect(clockAlarmDeviceLocal(summer).hour, isNot(19));
      expect(
        '${clockAlarmDeviceLocal(summer).hour.toString().padLeft(2, '0')}:'
        '${clockAlarmDeviceLocal(summer).minute.toString().padLeft(2, '0')}',
        formatHm(summer, 'Asia/Seoul'),
      );

      final laxWinter = zonedUtc(
        iana: 'America/Los_Angeles',
        year: 2026,
        month: 11,
        day: 28,
        hour: 21,
        minute: 0,
      );
      expect(formatHm(laxWinter, 'America/Los_Angeles'), '21:00');
      expect(formatHm(laxWinter, 'Asia/Seoul'), '14:00');
      expect(
        '${clockAlarmDeviceLocal(laxWinter).hour.toString().padLeft(2, '0')}:'
        '${clockAlarmDeviceLocal(laxWinter).minute.toString().padLeft(2, '0')}',
        formatHm(laxWinter, 'Asia/Seoul'),
      );

      final laxSummer = zonedUtc(
        iana: 'America/Los_Angeles',
        year: 2026,
        month: 7,
        day: 15,
        hour: 21,
        minute: 0,
      );
      expect(formatHm(laxSummer, 'America/Los_Angeles'), '21:00');
      expect(formatHm(laxSummer, 'Asia/Seoul'), '13:00');
      expect(
        '${clockAlarmDeviceLocal(laxSummer).hour.toString().padLeft(2, '0')}:'
        '${clockAlarmDeviceLocal(laxSummer).minute.toString().padLeft(2, '0')}',
        formatHm(laxSummer, 'Asia/Seoul'),
      );

      // A TZDateTime pickup must use the same device-local conversion.
      final pickup = zonedUtc(
        iana: 'Europe/Amsterdam',
        year: 2026,
        month: 11,
        day: 28,
        hour: 18,
        minute: 0,
      );
      final call = pickup.subtract(const Duration(hours: 1));
      expect(formatHm(call, 'Europe/Amsterdam'), '17:00');
      expect(formatHm(call, 'Asia/Seoul'), '01:00');
      expect(
        '${clockAlarmDeviceLocal(call).hour.toString().padLeft(2, '0')}:'
        '${clockAlarmDeviceLocal(call).minute.toString().padLeft(2, '0')}',
        formatHm(call, 'Asia/Seoul'),
      );
    });
  });

  group('JetlagGuideController guide sync', () {
    test(
      'schedules on enable, reschedules on change, cancels on off/clear',
      () async {
        final alerts = _RecordingAlerts();
        final now = DateTime.utc(2026, 11, 27, 12);
        final controller = JetlagGuideController(
          logStore: const JetlagLogStore(),
          alerts: alerts,
          clockAlarms: FakeClockAlarmLauncher(),
          now: () => now,
          schedule: _xx001().toSnapshot(),
        );
        addTearDown(controller.dispose);
        await controller.load();
        await _flush();

        expect(controller.caffeineAlertsEnabled, isFalse);
        expect(alerts.scheduled, isEmpty);

        final enabled = await controller.setCaffeineAlertsEnabled(true);
        expect(enabled, isTrue);
        expect(controller.caffeineAlertsEnabled, isTrue);
        expect(alerts.scheduled, isNotEmpty);
        final firstCount = alerts.scheduleCalls;
        final firstSignature = guideAlertSignature(alerts.scheduled);

        await _flush();
        expect(alerts.scheduleCalls, firstCount);

        controller.setUserSettings(
          controller.settings.copyWith(
            defaultBedTime: const DayTime(hour: 22, minute: 0),
            defaultWakeTime: const DayTime(hour: 6, minute: 0),
            chosenSleep: const Duration(hours: 5),
          ),
        );
        await _flush();
        expect(alerts.cancelRangeCount, greaterThan(0));
        expect(alerts.scheduleCalls, greaterThan(firstCount));
        expect(guideAlertSignature(alerts.scheduled), isNot(firstSignature));

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(JetlagAlertChannel.caffeineEnabledKey), isTrue);

        final beforeOffCancel = alerts.cancelRangeCount;
        final off = await controller.setCaffeineAlertsEnabled(false);
        expect(off, isTrue);
        expect(controller.caffeineAlertsEnabled, isFalse);
        expect(alerts.cancelRangeCount, greaterThan(beforeOffCancel));
        expect(prefs.getBool(JetlagAlertChannel.caffeineEnabledKey), isFalse);

        await controller.setMealAlertsEnabled(true);
        await controller.setBedAlertsEnabled(true);
        expect(controller.mealAlertsEnabled, isTrue);
        expect(controller.bedAlertsEnabled, isTrue);
        final beforeClear = alerts.cancelRangeCount;
        await controller.clearSchedule();
        expect(alerts.cancelRangeCount, greaterThan(beforeClear));
      },
    );

    test('permission denial keeps the switch off and does not save', () async {
      final alerts = _RecordingAlerts()..allowPermission = false;
      final controller = JetlagGuideController(
        logStore: const JetlagLogStore(),
        alerts: alerts,
        clockAlarms: FakeClockAlarmLauncher(),
        now: () => DateTime.utc(2026, 11, 27, 12),
        schedule: _xx001().toSnapshot(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      final ok = await controller.setMealAlertsEnabled(true);
      expect(ok, isFalse);
      expect(controller.mealAlertsEnabled, isFalse);
      expect(alerts.scheduled, isEmpty);
      expect(alerts.requestExactCount, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(JetlagAlertChannel.mealEnabledKey), isNull);
    });

    test('switch enables and prompts exact alarm when still denied', () async {
      final alerts = _RecordingAlerts()..exactAllowed = false;
      final controller = JetlagGuideController(
        logStore: const JetlagLogStore(),
        alerts: alerts,
        clockAlarms: FakeClockAlarmLauncher(),
        now: () => DateTime.utc(2026, 11, 27, 12),
        schedule: _xx001().toSnapshot(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      final ok = await controller.setBedAlertsEnabled(true);
      expect(ok, isTrue);
      expect(controller.bedAlertsEnabled, isTrue);
      expect(alerts.scheduled, isNotEmpty);
      expect(alerts.requestExactCount, 1);
      expect(controller.exactAlarmsAllowed, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(JetlagAlertChannel.bedEnabledKey), isTrue);
    });

    test('skips exact-alarm prompt when already allowed', () async {
      final alerts = _RecordingAlerts()..exactAllowed = true;
      final controller = JetlagGuideController(
        logStore: const JetlagLogStore(),
        alerts: alerts,
        clockAlarms: FakeClockAlarmLauncher(),
        now: () => DateTime.utc(2026, 11, 27, 12),
        schedule: _xx001().toSnapshot(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.setCaffeineAlertsEnabled(true), isTrue);
      expect(alerts.requestExactCount, 0);
      expect(controller.exactAlarmsAllowed, isTrue);
    });

    test('onAppResumed reschedules only when exact changes', () async {
      final alerts = _RecordingAlerts()..exactAllowed = false;
      final controller = JetlagGuideController(
        logStore: const JetlagLogStore(),
        alerts: alerts,
        clockAlarms: FakeClockAlarmLauncher(),
        now: () => DateTime.utc(2026, 11, 27, 12),
        schedule: _xx001().toSnapshot(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await controller.setCaffeineAlertsEnabled(true);
      await _flush();

      final afterEnableCalls = alerts.scheduleCalls;
      final afterEnableCancel = alerts.cancelRangeCount;

      await controller.onAppResumed();
      await _flush();
      expect(alerts.scheduleCalls, afterEnableCalls);
      expect(alerts.cancelRangeCount, afterEnableCancel);

      alerts.exactAllowed = true;
      await controller.onAppResumed();
      await _flush();
      expect(controller.exactAlarmsAllowed, isTrue);
      expect(alerts.cancelRangeCount, greaterThan(afterEnableCancel));
      expect(alerts.scheduleCalls, greaterThan(afterEnableCalls));
      expect(alerts.scheduled, isNotEmpty);

      final afterChangeCalls = alerts.scheduleCalls;
      final afterChangeCancel = alerts.cancelRangeCount;
      await controller.onAppResumed();
      await _flush();
      expect(alerts.scheduleCalls, afterChangeCalls);
      expect(alerts.cancelRangeCount, afterChangeCancel);
    });

    test(
      'registerClockAlarm uses device local hour/minute inside 24h',
      () async {
        final launcher = FakeClockAlarmLauncher();
        final now = DateTime.utc(2026, 11, 27, 12);
        final controller = JetlagGuideController(
          logStore: const JetlagLogStore(),
          alerts: _RecordingAlerts(),
          clockAlarms: launcher,
          now: () => now,
          schedule: _xx001().toSnapshot(),
        );
        addTearDown(controller.dispose);
        await controller.load();

        // Planned wake at 21:00 Amsterdam in winter — a TZDateTime.
        final when = zonedUtc(
          iana: 'Europe/Amsterdam',
          year: 2026,
          month: 11,
          day: 27,
          hour: 21,
          minute: 0,
        );
        expect(when.isAfter(now), isTrue);
        expect(when.isBefore(now.add(const Duration(hours: 24))), isTrue);
        await controller.registerClockAlarm(
          whenUtc: when,
          message: kClockAlarmWakeMessage,
        );
        expect(launcher.calls, hasLength(1));
        final local = clockAlarmDeviceLocal(when);
        expect(launcher.calls.single.hour, local.hour);
        expect(launcher.calls.single.minutes, local.minute);
        expect(launcher.calls.single.hour, isNot(when.toUtc().hour));
        expect(launcher.calls.single.message, kClockAlarmWakeMessage);

        final wakeupWhen = zonedUtc(
          iana: 'Europe/Amsterdam',
          year: 2026,
          month: 11,
          day: 27,
          hour: 18,
          minute: 0,
        ).subtract(const Duration(hours: 1));
        await controller.registerClockAlarm(
          whenUtc: wakeupWhen,
          message: kClockAlarmWakeupCallMessage,
        );
        expect(launcher.calls, hasLength(2));
        expect(
          launcher.calls.last.hour,
          clockAlarmDeviceLocal(wakeupWhen).hour,
        );
        expect(launcher.calls.last.message, kClockAlarmWakeupCallMessage);

        await controller.registerClockAlarm(
          whenUtc: now.add(const Duration(hours: 25)),
          message: kClockAlarmWakeMessage,
        );
        expect(launcher.calls, hasLength(2));
      },
    );

    test('legacy wake/pickup keys are not re-enabled on load', () async {
      SharedPreferences.setMockInitialValues({
        JetlagAlertChannel.enabledKey: true,
        JetlagAlertChannel.wakeEnabledKey: true,
      });
      final alerts = _RecordingAlerts();
      final controller = JetlagGuideController(
        logStore: const JetlagLogStore(),
        alerts: alerts,
        clockAlarms: FakeClockAlarmLauncher(),
        now: () => DateTime.utc(2026, 11, 27, 12),
        schedule: _xx001().toSnapshot(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await _flush();
      expect(controller.caffeineAlertsEnabled, isFalse);
      expect(controller.mealAlertsEnabled, isFalse);
      expect(controller.bedAlertsEnabled, isFalse);
      expect(
        alerts.cancelCalls,
        contains(JetlagAlertChannel.pickupNotificationId),
      );
      expect(
        alerts.cancelRanges.any(
          (range) => range.start == JetlagAlertChannel.wakeIdStart,
        ),
        isTrue,
      );
    });
  });

  test('AndroidManifest declares SET_ALARM and keeps notification receivers', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest.contains('android.permission.POST_NOTIFICATIONS'), isTrue);
    expect(manifest.contains('android.permission.VIBRATE'), isTrue);
    expect(
      manifest.contains('android.permission.RECEIVE_BOOT_COMPLETED'),
      isTrue,
    );
    expect(
      manifest.contains('android.permission.SCHEDULE_EXACT_ALARM'),
      isTrue,
    );
    expect(manifest.contains('com.android.alarm.permission.SET_ALARM'), isTrue);
    expect(manifest.contains('android.permission.USE_EXACT_ALARM'), isFalse);
    expect(manifest.contains('android.intent.action.SET_ALARM'), isTrue);
    expect(
      manifest.contains(
        'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver',
      ),
      isTrue,
    );
    expect(
      manifest.contains(
        'com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver',
      ),
      isTrue,
    );
  });

  testWidgets('records page shows guide switches and clock alarms at 360dp', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final overflows = <String>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) {
        overflows.add(details.exceptionAsString());
      }
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(MyApp(schedule: _xx001()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('기록·설정'));
      await tester.pumpAndSettle();

      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('jetlag-records-page')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('jetlag-caffeine-switch')),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('jetlag-caffeine-switch')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('jetlag-meal-switch')), findsOneWidget);
      expect(find.byKey(const ValueKey('jetlag-bed-switch')), findsOneWidget);
      expect(find.text('픽업 알림'), findsNothing);
      expect(find.text('기상 알림'), findsNothing);
      expect(find.byKey(const ValueKey('jetlag-wake-exact')), findsNothing);
      expect(find.text('정확한 알람 허용'), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('jetlag-wake-test')),
        100,
        scrollable: scrollable,
      );
      expect(find.byKey(const ValueKey('jetlag-wake-test')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('jetlag-clock-wake')),
        100,
        scrollable: scrollable,
      );
      expect(find.byKey(const ValueKey('jetlag-clock-wake')), findsOneWidget);
      expect(find.text('시계 알람'), findsOneWidget);
      expect(overflows, isEmpty);
      expect(find.textContaining('권장'), findsNothing);
      expect(find.textContaining('치료'), findsNothing);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(MyApp(schedule: _xx001()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('기록·설정'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('jetlag-clock-wake')), findsNothing);
      expect(find.text('시계 알람'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

FlightScheduleInput _xx001() {
  return FlightScheduleInput(
    flightNumber: 'XX001',
    origin: 'ICN',
    destination: 'AMS',
    destinationTimeZone: 'Europe/Amsterdam',
    referenceTimeZone: 'Asia/Seoul',
    sta: DateTime.utc(2026, 11, 27, 14),
    std: DateTime.utc(2026, 11, 28, 20, 15),
    pickup: DateTime.utc(2026, 11, 28, 18, 5),
    blockMinutes: 11 * 60,
  );
}

class _RecordingAlerts implements JetlagAlertScheduler {
  final scheduled = <GuideAlert>[];
  int scheduleCalls = 0;
  int cancelRangeCount = 0;
  final cancelCalls = <int>[];
  final cancelRanges = <({int start, int count})>[];
  bool allowPermission = true;
  bool exactAllowed = true;
  int requestExactCount = 0;

  @override
  Future<void> cancel({required int id}) async {
    cancelCalls.add(id);
  }

  @override
  Future<void> cancelRange({required int start, required int count}) async {
    cancelRangeCount += 1;
    cancelRanges.add((start: start, count: count));
    scheduled.removeWhere(
      (alert) => alert.id >= start && alert.id < start + count,
    );
  }

  @override
  Future<bool> ensureChannel() async => true;

  @override
  Future<bool> requestPermission() async => allowPermission;

  @override
  Future<void> scheduleAlert({
    required int id,
    required DateTime whenUtc,
    required String title,
    required String body,
  }) async {
    scheduleCalls += 1;
    scheduled.add(
      GuideAlert(id: id, whenUtc: whenUtc, title: title, body: body),
    );
  }

  @override
  Future<bool> canScheduleExact() async => exactAllowed;

  @override
  Future<void> requestExactAlarm() async {
    requestExactCount += 1;
  }

  @override
  Future<void> scheduleTestAlert({
    required DateTime whenUtc,
    required String localIana,
    required String homeIana,
  }) async {}
}
