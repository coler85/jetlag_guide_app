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
import 'package:jetlag_guide_app/theme/jetlag_theme.dart';
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
    expect(plan.recommendedStartUtc, DateTime.utc(2026, 6, 4, 11, 15));
    expect(plan.recommendedEndUtc, DateTime.utc(2026, 6, 4, 18, 15));
    expect(plan.shortfall, const Duration(hours: 2, minutes: 45));

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
    expect(early.single.startUtc, DateTime.utc(2026, 6, 4, 11, 15));
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
    expect(logged.dashboard.sleepDebtLabel, '-1시간 30분');
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
    const target = Duration(hours: 8);
    final night = SleepLog(
      id: 'night',
      startUtc: DateTime.utc(2026, 6, 4, 10, 15),
      endUtc: DateTime.utc(2026, 6, 4, 15, 45),
      scheduleKey: schedule.key,
    );

    final empty = calculator.evaluate(target: target, logs: const []);
    expect(empty.balance, Duration.zero);
    expect(empty.label, '수면 기록 없음');
    expect(empty.inDebt, isFalse);
    expect(departure.shortfall, const Duration(hours: 2, minutes: 45));

    final logged = calculator.evaluate(target: target, logs: [night]);
    expect(logged.balance, const Duration(hours: -2, minutes: -30));
    expect(logged.label, '-2시간 30분');
    expect(logged.inDebt, isTrue);

    final cleared = calculator.evaluate(target: target, logs: const []);
    expect(cleared.balance, Duration.zero);
    expect(cleared.label, '수면 기록 없음');
    expect(cleared.inDebt, isFalse);
  });

  test(
    'sleep at or above the target shows zero and ignores the dawn estimate',
    () {
      final schedule = _laxLayover();
      const target = Duration(hours: 8);
      final debt = const SleepDebtCalculator().evaluate(
        target: target,
        logs: [
          SleepLog(
            id: 'full',
            startUtc: DateTime.utc(2026, 6, 5, 2),
            endUtc: DateTime.utc(2026, 6, 5, 10),
            scheduleKey: 'x',
          ),
        ],
      );
      expect(debt.label, '0분');
      expect(debt.inDebt, isFalse);

      final ahead = const SleepDebtCalculator().evaluate(
        target: target,
        logs: [
          SleepLog(
            id: 'long',
            startUtc: DateTime.utc(2026, 6, 1),
            endUtc: DateTime.utc(2026, 6, 1, 9),
            scheduleKey: 'x',
          ),
        ],
      );
      expect(ahead.label, '0분');
      expect(ahead.inDebt, isFalse);

      final away = const JetLagCalculator().calculate(
        schedule: schedule,
        lifestyle: JetlagLifestyle.kstAnchor,
        logs: const [],
        sleepLogs: [
          SleepLog(
            id: 'short-elsewhere',
            startUtc: DateTime.utc(2026, 6, 5, 2),
            endUtc: DateTime.utc(2026, 6, 5, 8),
            scheduleKey: schedule.key,
          ),
        ],
        now: DateTime.utc(2026, 6, 4, 12),
        homeBaseTimezone: 'Asia/Seoul',
      );
      expect(away.dashboard.sleepDebtLabel, '-1시간');
      expect(away.dashboard.sleepDebtInDebt, isTrue);
      final block = away.events.where(
        (event) => event.kind == GuideEventKind.loggedSleep,
      );
      expect(block.single.title, '기록한 수면');
      expect(block.single.startUtc, DateTime.utc(2026, 6, 5, 2));
      expect(block.single.endUtc, DateTime.utc(2026, 6, 5, 8));
      expect(
        JetlagTheme.accentFor(GuideEventKind.loggedSleep),
        isNot(JetlagTheme.accentFor(GuideEventKind.sleep)),
      );
    },
  );

  test(
    'a 7 hour target and an 8 hour target change the block and the debt',
    () {
      final schedule = _laxLayover();
      final slept = SleepLog(
        id: 'six',
        startUtc: DateTime.utc(2026, 6, 4, 12),
        endUtc: DateTime.utc(2026, 6, 4, 18),
        scheduleKey: schedule.key,
      );
      final atSeven = _targeted(schedule, const Duration(hours: 7), slept);
      final atEight = _targeted(schedule, const Duration(hours: 8), slept);

      expect(_earlyLength(atSeven), const Duration(hours: 7));
      expect(_earlyLength(atEight), const Duration(hours: 8));
      expect(atSeven.dashboard.sleepDebtLabel, '-1시간');
      expect(atEight.dashboard.sleepDebtLabel, '-2시간');
      expect(UserSettings.defaults.sleepTarget, const Duration(hours: 7));
    },
  );

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
    expect(loaded.sleepTarget, const Duration(hours: 7));
  });

  test(
    'sleep target is saved on 30 minute steps between 4 and 9 hours',
    () async {
      const store = UserSettingsStore();
      expect(UserSettings.defaults.sleepTarget, const Duration(hours: 7));
      expect((await store.load()).sleepTarget, const Duration(hours: 7));

      await store.save(const UserSettings(chosenSleep: Duration(hours: 8)));
      expect((await store.load()).sleepTarget, const Duration(hours: 8));

      await store.save(
        const UserSettings(chosenSleep: Duration(hours: 7, minutes: 30)),
      );
      expect(
        (await store.load()).sleepTarget,
        const Duration(hours: 7, minutes: 30),
      );

      await store.save(const UserSettings(chosenSleep: Duration(hours: 3)));
      expect((await store.load()).sleepTarget, const Duration(hours: 4));

      await store.save(const UserSettings(chosenSleep: Duration(hours: 12)));
      expect((await store.load()).sleepTarget, const Duration(hours: 9));

      await store.save(
        const UserSettings(chosenSleep: Duration(hours: 7, minutes: 20)),
      );
      expect(
        (await store.load()).sleepTarget,
        const Duration(hours: 7, minutes: 30),
      );
    },
  );

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
    flightNumber: 'XX000',
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
      flightNumber: 'XX000',
    ),
    lifestyle: JetlagLifestyle.hybrid,
    logs: const [],
    now: DateTime.utc(2026, 6, 4, 8),
    homeBaseTimezone: 'Asia/Seoul',
    settings: UserSettings(hybridMaxShiftHours: capHours),
  );
}

JetLagTimeline _targeted(
  JetlagScheduleSnapshot schedule,
  Duration target,
  SleepLog slept,
) {
  return const JetLagCalculator().calculate(
    schedule: schedule,
    lifestyle: JetlagLifestyle.kstAnchor,
    logs: const [],
    sleepLogs: [slept],
    now: DateTime.utc(2026, 6, 4, 12),
    homeBaseTimezone: 'Asia/Seoul',
    settings: UserSettings(chosenSleep: target),
  );
}

Duration _earlyLength(JetLagTimeline timeline) {
  final early = timeline.events.singleWhere(
    (event) =>
        event.kind == GuideEventKind.sleep && event.detail.contains('미리'),
  );
  return early.endUtc!.difference(early.startUtc);
}

String _homeBed(JetLagTimeline timeline) {
  final sleep = timeline.events.firstWhere(
    (event) =>
        event.kind == GuideEventKind.sleep && !event.detail.contains('미리'),
  );
  return formatHm(sleep.startUtc, 'Asia/Seoul');
}
