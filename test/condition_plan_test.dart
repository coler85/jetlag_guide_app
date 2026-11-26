import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/logic/home_departure.dart';
import 'package:jetlag_guide_app/logic/hybrid_strategy.dart';
import 'package:jetlag_guide_app/logic/jetlag_calculator.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:jetlag_guide_app/logic/sleep_debt.dart';
import 'package:jetlag_guide_app/models/guide_event.dart';
import 'package:jetlag_guide_app/models/jetlag_schedule.dart';
import 'package:jetlag_guide_app/models/lifestyle.dart';
import 'package:jetlag_guide_app/models/sleep_log.dart';
import 'package:jetlag_guide_app/models/user_settings.dart';
import 'package:jetlag_guide_app/state/user_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ensureJetlagTimeZones();
  });

  test('hybrid shift follows the gap inside the cap and stops at the cap', () {
    const strategy = HybridStrategy();
    final seoulLax = zoneOffset(
      DateTime.utc(2026, 6, 4, 12),
      'America/Los_Angeles',
      'Asia/Seoul',
    );
    expect(
      strategy.shift(zoneOffset: seoulLax, maxShift: const Duration(hours: 3)),
      const Duration(hours: -3),
    );
    expect(
      strategy.shift(zoneOffset: seoulLax, maxShift: const Duration(hours: 6)),
      const Duration(hours: -6),
    );

    final seoulShanghai = zoneOffset(
      DateTime.utc(2026, 6, 4, 12),
      'Asia/Shanghai',
      'Asia/Seoul',
    );
    expect(
      strategy.shift(
        zoneOffset: seoulShanghai,
        maxShift: const Duration(hours: 3),
      ),
      const Duration(hours: 1),
    );
  });

  test('dawn show-up pulls the night forward and counts the cut as debt', () {
    final schedule = _laxLayover();
    final plan = const HomeDepartureAdvisor().evaluate(
      schedule: schedule,
      settings: UserSettings.defaults,
    );

    expect(plan.applies, isTrue);
    expect(plan.reportUtc, DateTime.utc(2026, 6, 4, 20));
    expect(plan.forcedWakeUtc, DateTime.utc(2026, 6, 4, 18, 15));
    expect(plan.naturalBedUtc, DateTime.utc(2026, 6, 4, 14));
    expect(plan.naturalWakeUtc, DateTime.utc(2026, 6, 4, 22));
    expect(plan.recommendedStartUtc, DateTime.utc(2026, 6, 4, 10, 15));
    expect(plan.recommendedEndUtc, DateTime.utc(2026, 6, 4, 18, 15));
    expect(plan.shortfall, const Duration(hours: 3, minutes: 45));

    final timeline = const JetLagCalculator().calculate(
      schedule: schedule,
      lifestyle: JetlagLifestyle.kstAnchor,
      logs: const [],
      now: DateTime.utc(2026, 6, 4, 12),
      homeBaseTimezone: 'Asia/Seoul',
    );
    final early = timeline.events.where(
      (event) =>
          event.kind == GuideEventKind.sleep && event.detail.contains('미리'),
    );
    expect(early.single.startUtc, DateTime.utc(2026, 6, 4, 10, 15));
    expect(early.single.endUtc, DateTime.utc(2026, 6, 4, 18, 15));
    expect(timeline.dashboard.sleepDebtLabel, '수면 기록 없음');
    expect(timeline.dashboard.sleepDebtInDebt, isFalse);
    expect(timeline.dashboard.sleepDebtRecorded, isFalse);

    final logged = const JetLagCalculator().calculate(
      schedule: schedule,
      lifestyle: JetlagLifestyle.kstAnchor,
      logs: const [],
      sleepLogs: [
        SleepLog(
          id: 'night',
          startUtc: DateTime.utc(2026, 6, 4, 10, 15),
          endUtc: DateTime.utc(2026, 6, 4, 15, 45),
          scheduleKey: schedule.key,
        ),
      ],
      now: DateTime.utc(2026, 6, 4, 12),
      homeBaseTimezone: 'Asia/Seoul',
    );
    expect(logged.dashboard.sleepDebtLabel, '-2시간 30분');
    expect(logged.dashboard.sleepDebtInDebt, isTrue);
    expect(logged.dashboard.sleepDebtRecorded, isTrue);
  });

  test('sleep debt is zero with no logs, then the logged night, then zero', () {
    final schedule = _laxLayover();
    final departure = const HomeDepartureAdvisor().evaluate(
      schedule: schedule,
      settings: UserSettings.defaults,
    );
    const calculator = SleepDebtCalculator();
    const usual = Duration(hours: 8);
    final night = SleepLog(
      id: 'night',
      startUtc: DateTime.utc(2026, 6, 4, 10, 15),
      endUtc: DateTime.utc(2026, 6, 4, 15, 45),
      scheduleKey: schedule.key,
    );

    final empty = calculator.evaluate(
      usual: usual,
      logs: const [],
      departure: departure,
    );
    expect(empty.balance, Duration.zero);
    expect(empty.label, '수면 기록 없음');
    expect(empty.inDebt, isFalse);

    final logged = calculator.evaluate(
      usual: usual,
      logs: [night],
      departure: departure,
    );
    expect(logged.balance, const Duration(hours: -2, minutes: -30));
    expect(logged.label, '-2시간 30분');
    expect(logged.inDebt, isTrue);

    final cleared = calculator.evaluate(
      usual: usual,
      logs: const [],
      departure: departure,
    );
    expect(cleared.balance, Duration.zero);
    expect(cleared.label, '수면 기록 없음');
    expect(cleared.inDebt, isFalse);
  });

  test('a full logged night clears the show-up estimate', () {
    final schedule = _laxLayover();
    final debt = const SleepDebtCalculator().evaluate(
      usual: const Duration(hours: 8),
      logs: [
        SleepLog(
          id: 'full',
          startUtc: DateTime.utc(2026, 6, 4, 10, 15),
          endUtc: DateTime.utc(2026, 6, 4, 18, 15),
          scheduleKey: 'x',
        ),
      ],
      departure: const HomeDepartureAdvisor().evaluate(
        schedule: schedule,
        settings: UserSettings.defaults,
      ),
    );
    expect(debt.label, '0분');
    expect(debt.inDebt, isFalse);

    final ahead = const SleepDebtCalculator().evaluate(
      usual: const Duration(hours: 8),
      logs: [
        SleepLog(
          id: 'long',
          startUtc: DateTime.utc(2026, 6, 1),
          endUtc: DateTime.utc(2026, 6, 1, 9),
          scheduleKey: 'x',
        ),
      ],
    );
    expect(ahead.label, '+1시간');
    expect(ahead.inDebt, isFalse);
  });

  test('hybrid cap moves anchors by the limit, not all the way to local', () {
    final capped = _hybridTimeline(3);
    final loose = _hybridTimeline(6);
    expect(_homeBed(capped), '20:00');
    expect(_homeBed(loose), '17:00');
  });

  test('user settings survive shared preferences', () async {
    const store = UserSettingsStore();
    await store.save(
      const UserSettings(
        defaultBedTime: DayTime(hour: 22, minute: 30),
        defaultWakeTime: DayTime(hour: 6, minute: 15),
        prepTime: Duration(minutes: 30),
        commuteTime: Duration(minutes: 90),
        hybridMaxShiftHours: 4,
      ),
    );
    final loaded = await store.load();
    expect(loaded.defaultBedTime.label, '22:30');
    expect(loaded.defaultWakeTime.label, '06:15');
    expect(loaded.prepTime, const Duration(minutes: 30));
    expect(loaded.commuteTime, const Duration(minutes: 90));
    expect(loaded.hybridMaxShiftHours, 4);
    expect(loaded.usualSleep, const Duration(hours: 7, minutes: 45));
    expect(loaded.homeShowupLead, const Duration(minutes: 95));
  });

  test(
    'home show-up lead is saved, restored, and kept within 0 to 240',
    () async {
      const store = UserSettingsStore();
      expect(UserSettings.defaults.homeShowupLead, const Duration(minutes: 95));
      expect((await store.load()).homeShowupLead, const Duration(minutes: 95));

      await store.save(
        const UserSettings(homeShowupLead: Duration(minutes: 120)),
      );
      expect((await store.load()).homeShowupLead, const Duration(minutes: 120));

      await store.save(
        const UserSettings(homeShowupLead: Duration(minutes: 500)),
      );
      expect((await store.load()).homeShowupLead, const Duration(minutes: 240));

      await store.save(
        const UserSettings(homeShowupLead: Duration(minutes: -15)),
      );
      expect((await store.load()).homeShowupLead, Duration.zero);
    },
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
    flightNumber: 'KE017',
  );
}

JetLagTimeline _hybridTimeline(int capHours) {
  return const JetLagCalculator().calculate(
    schedule: JetlagScheduleSnapshot(
      stationLabel: 'LAX',
      originLabel: 'ICN',
      localTimeZone: 'America/Los_Angeles',
      referenceTimeZone: 'Asia/Seoul',
      staUtc: DateTime.utc(2026, 6, 3, 17),
      stdUtc: DateTime.utc(2026, 6, 6, 17),
      pickupUtc: DateTime.utc(2026, 6, 5, 3),
      flightNumber: 'KE017',
    ),
    lifestyle: JetlagLifestyle.hybrid,
    logs: const [],
    now: DateTime.utc(2026, 6, 4, 8),
    homeBaseTimezone: 'Asia/Seoul',
    settings: UserSettings(hybridMaxShiftHours: capHours),
  );
}

String _homeBed(JetLagTimeline timeline) {
  final sleep = timeline.events.firstWhere(
    (event) =>
        event.kind == GuideEventKind.sleep && !event.detail.contains('미리'),
  );
  return formatHm(sleep.startUtc, 'Asia/Seoul');
}
