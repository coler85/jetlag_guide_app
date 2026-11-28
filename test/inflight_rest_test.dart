import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/logic/bunk_plan.dart';
import 'package:jetlag_guide_app/logic/guide_plan.dart';
import 'package:jetlag_guide_app/logic/inflight_rest.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:jetlag_guide_app/models/bunk_shift.dart';
import 'package:jetlag_guide_app/models/guide_event.dart';
import 'package:jetlag_guide_app/models/jetlag_schedule.dart';
import 'package:jetlag_guide_app/models/lifestyle.dart';
import 'package:jetlag_guide_app/models/user_settings.dart';
import 'package:jetlag_guide_app/theme/jetlag_theme.dart';
import 'package:jetlag_guide_app/widgets/bunk_selection_card.dart';
import 'package:jetlag_guide_app/widgets/guide_event_card.dart';

/// XX000 leaves home and lands at SFO at the sample STA. The block is 11 hours.
/// XX001 leaves that SFO departure and lands 11 hours later.
void main() {
  setUp(ensureJetlagTimeZones);

  const home = 'Asia/Seoul';
  const sfo = 'America/Los_Angeles';
  const ams = 'Europe/Amsterdam';

  final outboundStd = DateTime.utc(2026, 11, 29, 6, 35);
  final outboundSta = DateTime.utc(2026, 11, 29, 17, 35);
  final returnStd = DateTime.utc(2026, 12, 1, 19, 45);
  final returnSta = DateTime.utc(2026, 12, 2, 6, 45);

  InflightRestWindow window({
    required bool outbound,
    required JetlagLifestyle lifestyle,
  }) {
    return inflightRestWindow(
      stdUtc: outbound ? outboundStd : returnStd,
      staUtc: outbound ? outboundSta : returnSta,
      originZone: outbound ? home : sfo,
      destinationZone: outbound ? sfo : home,
      homeZone: home,
      lifestyle: lifestyle,
    )!;
  }

  JetlagScheduleSnapshot xx000Layover() {
    return JetlagScheduleSnapshot(
      stationLabel: 'SFO',
      originLabel: 'ICN',
      localTimeZone: sfo,
      referenceTimeZone: home,
      staUtc: outboundSta,
      stdUtc: returnStd,
      flightNumber: 'XX000',
      blockMinutes: 11 * 60,
    );
  }

  /// Round-trip layover at AMS: outbound arrival = station STA, return STD.
  JetlagScheduleSnapshot amsLayover({
    DateTime? staUtc,
  }) {
    return JetlagScheduleSnapshot(
      stationLabel: 'AMS',
      originLabel: 'ICN',
      localTimeZone: ams,
      referenceTimeZone: home,
      staUtc: staUtc ?? DateTime.utc(2026, 11, 27, 14),
      stdUtc: DateTime.utc(2026, 11, 28, 20, 15),
      flightNumber: 'XX001',
      blockMinutes: 11 * 60,
    );
  }

  test('XX000 outbound windows follow the home night plus the inflight move', () {
    final anchor = window(outbound: true, lifestyle: JetlagLifestyle.kstAnchor);
    final hybrid = window(outbound: true, lifestyle: JetlagLifestyle.hybrid);
    final local = window(outbound: true, lifestyle: JetlagLifestyle.localAdapt);

    expect(anchor.inflightShift, Duration.zero);
    expect(anchor.shortOverlap, isFalse);
    expect(anchor.missedNight, isFalse);
    expect(anchor.startUtc, DateTime.utc(2026, 11, 29, 14));
    expect(anchor.endUtc, DateTime.utc(2026, 11, 29, 16, 35));
    expect(anchor.headline, contains('한국 기준 밤에 가까운 시간대예요.'));
    expect(anchor.supplement, contains('실제 휴식은 크루 배정에 따릅니다.'));
    expect(anchor.detail, contains('한국 기준 밤에 가까운 시간대예요.'));
    expect(anchor.detail, contains('실제 휴식은 크루 배정에 따릅니다.'));
    expect(anchor.detail.contains('짧아요'), isFalse);
    expect(anchor.detail.contains('겹치지 않아요'), isFalse);
    expect(anchor.detail.contains('잠을 보충해 보세요'), isFalse);

    expect(hybrid.inflightShift, const Duration(minutes: -90));
    expect(hybrid.shortOverlap, isFalse);
    expect(hybrid.missedNight, isFalse);
    expect(hybrid.startUtc, DateTime.utc(2026, 11, 29, 12, 30));
    expect(hybrid.endUtc, DateTime.utc(2026, 11, 29, 16, 35));
    expect(hybrid.detail, contains('1시간 30분'));
    expect(hybrid.detail, contains('실제 휴식은 크루 배정에 따릅니다.'));

    // Home night moved earlier by the 3 hour cap, not the SFO night.
    // A destination-night overlap would start at 07:05Z (23:00 PST).
    expect(local.inflightShift, const Duration(hours: -3));
    expect(local.shortOverlap, isFalse);
    expect(local.missedNight, isFalse);
    expect(local.startUtc, DateTime.utc(2026, 11, 29, 11));
    expect(local.endUtc, DateTime.utc(2026, 11, 29, 16, 35));
    expect(local.startUtc, isNot(DateTime.utc(2026, 11, 29, 7, 5)));
    expect(formatHm(local.startUtc, home), '20:00');
    expect(local.detail, contains('3시간'));
    expect(local.detail.contains('짧아요'), isFalse);
  });

  test('XX001 return windows keep the layover mode and move toward home', () {
    final anchor = window(outbound: false, lifestyle: JetlagLifestyle.kstAnchor);
    final hybrid = window(outbound: false, lifestyle: JetlagLifestyle.hybrid);
    final local = window(outbound: false, lifestyle: JetlagLifestyle.localAdapt);

    expect(anchor.inflightShift, Duration.zero);
    expect(anchor.shortOverlap, isFalse);
    expect(anchor.missedNight, isFalse);
    expect(anchor.startUtc, DateTime.utc(2026, 12, 1, 20, 15));
    expect(anchor.endUtc, DateTime.utc(2026, 12, 1, 22));
    expect(anchor.detail, contains('한국 기준 밤에 가까운 시간대예요.'));

    // Hybrid night meets cruise for 15 minutes — show the real clipped span.
    expect(hybrid.inflightShift, const Duration(minutes: 90));
    expect(hybrid.shortOverlap, isTrue);
    expect(hybrid.missedNight, isFalse);
    expect(hybrid.startUtc, DateTime.utc(2026, 12, 1, 20, 15));
    expect(hybrid.endUtc, DateTime.utc(2026, 12, 1, 20, 30));
    expect(
      hybrid.headline,
      contains('생체시계 밤이 이륙 직후 끝나서 겹치는 시간이 짧아요.'),
    );
    expect(
      hybrid.supplement,
      contains('실제 휴식은 크루 배정에 따르고, 컨디션에 맞춰 90분 이내로 잠을 보충해 보세요.'),
    );
    expect(
      hybrid.detail,
      contains('생체시계 밤이 이륙 직후 끝나서 겹치는 시간이 짧아요.'),
    );
    expect(
      hybrid.detail,
      contains('실제 휴식은 크루 배정에 따르고, 컨디션에 맞춰 90분 이내로 잠을 보충해 보세요.'),
    );
    expect(hybrid.detail.contains('겹치지 않아요'), isFalse);
    expect(hybrid.detail.contains('1시간 30분'), isFalse);

    // Local-adapt night misses the cruise entirely — nearest 90-minute slice.
    expect(local.inflightShift, const Duration(hours: 3));
    expect(local.shortOverlap, isTrue);
    expect(local.missedNight, isTrue);
    expect(local.startUtc, DateTime.utc(2026, 12, 1, 20, 15));
    expect(local.endUtc, DateTime.utc(2026, 12, 1, 21, 45));
    expect(local.headline, contains('생체시계 밤과 겹치지 않아요.'));
    expect(local.detail, contains('생체시계 밤과 겹치지 않아요.'));
    expect(
      local.detail,
      contains('실제 휴식은 크루 배정에 따르고, 컨디션에 맞춰 90분 이내로 잠을 보충해 보세요.'),
    );
    expect(local.detail.contains('짧아요'), isFalse);
    expect(local.detail.contains('3시간'), isFalse);
  });

  test(
    'AMS 21:15 kstAnchor keeps the real 75-minute overlap, not a 90-minute slice',
    () {
      final std = DateTime.utc(2026, 11, 28, 20, 15);
      final sta = std.add(const Duration(hours: 11));
      final result = inflightRestWindow(
        stdUtc: std,
        staUtc: sta,
        originZone: ams,
        destinationZone: home,
        homeZone: home,
        lifestyle: JetlagLifestyle.kstAnchor,
      )!;

      expect(result.startUtc, DateTime.utc(2026, 11, 28, 20, 45));
      expect(result.endUtc, DateTime.utc(2026, 11, 28, 22));
      expect(result.endUtc.difference(result.startUtc), const Duration(minutes: 75));
      expect(result.shortOverlap, isTrue);
      expect(result.missedNight, isFalse);
      expect(result.detail.contains('겹치지 않아요'), isFalse);
      expect(
        result.headline,
        contains('한국 밤이 이륙 직후 끝나서 겹치는 시간이 짧아요.'),
      );
      expect(
        result.detail,
        contains('한국 밤이 이륙 직후 끝나서 겹치는 시간이 짧아요.'),
      );
      expect(formatHm(result.startUtc, ams), '21:45');
      expect(formatHm(result.endUtc, ams), '23:00');
      expect(formatHm(result.startUtc, home), '05:45');
      expect(formatHm(result.endUtc, home), '07:00');
      // Nearest 90-minute slice from cruise start would end at 23:15 AMS.
      expect(formatHm(result.endUtc, ams), isNot('23:15'));
      expect(
        result.endUtc,
        isNot(DateTime.utc(2026, 11, 28, 20, 45).add(const Duration(minutes: 90))),
      );

      final line = inflightRestReferenceLine(
        startUtc: result.startUtc,
        endUtc: result.endUtc,
        missedNight: result.missedNight,
        localIana: ams,
        localTag: 'AMS',
        homeIana: home,
      );
      expect(
        line,
        '생체시계 밤과 겹치는 시간 21:45–23:00 (AMS) · 05:45–07:00 KST',
      );
      expect(line.contains('가까운 시간'), isFalse);
      expect(line.contains('Z'), isFalse);

      final viaSchedule = layoverReturnInflightRest(
        stdUtc: std,
        blockMinutes: 11 * 60,
        originZone: ams,
        destinationZone: home,
        homeZone: home,
        lifestyle: JetlagLifestyle.kstAnchor,
      )!;
      expect(viaSchedule.startUtc, result.startUtc);
      expect(viaSchedule.endUtc, result.endUtc);
      expect(viaSchedule.missedNight, result.missedNight);
      expect(viaSchedule.headline, result.headline);
    },
  );

  testWidgets(
    'AMS 21:15 standalone inflight card uses the same clock rows as other events',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final std = DateTime.utc(2026, 11, 28, 20, 15);
      final sta = std.add(const Duration(hours: 11));
      final result = inflightRestWindow(
        stdUtc: std,
        staUtc: sta,
        originZone: ams,
        destinationZone: home,
        homeZone: home,
        lifestyle: JetlagLifestyle.kstAnchor,
      )!;
      final clocks = formatTripleClock(
        startUtc: result.startUtc,
        endUtc: result.endUtc,
        localIana: ams,
        localTag: 'AMS',
        homeIana: home,
      );
      expect(clocks.local, '21:45 - 23:00 (AMS)');
      expect(clocks.supporting, contains('KST'));
      expect(clocks.supporting, contains('20:45Z - 22:00Z'));
      expect(clocks.supporting.contains('20:45 - 22:00Z'), isFalse);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: GuideEventCard(
              event: GuideEvent(
                id: 'inflight-ams-sample',
                kind: GuideEventKind.inflight,
                startUtc: result.startUtc,
                endUtc: result.endUtc,
                title: '기내 휴식',
                detail: result.detail,
                inflightMissedNight: result.missedNight,
              ),
              localClock: clocks.local,
              supportingClock: clocks.supporting,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(clocks.local), findsOneWidget);
      expect(find.text(clocks.supporting), findsOneWidget);
      expect(find.text('기내 휴식'), findsOneWidget);
      expect(find.text(result.detail), findsOneWidget);
      expect(find.textContaining('생체시계 밤과 겹치는 시간'), findsNothing);
      expect(
        tester.getTopLeft(find.text(clocks.local)).dy,
        lessThan(tester.getTopLeft(find.text('기내 휴식')).dy),
      );
      expect(
        tester.getTopLeft(find.text('기내 휴식')).dy,
        lessThan(tester.getTopLeft(find.text(result.detail)).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('the XX000 layover timeline shows the return inflight window', () {
    final shown = buildGuideEvents(
      xx000Layover(),
      lifestyle: JetlagLifestyle.localAdapt,
    ).where((event) => event.kind == GuideEventKind.inflight);

    expect(shown, hasLength(1));
    expect(shown.single.startUtc, DateTime.utc(2026, 12, 1, 20, 15));
    expect(shown.single.endUtc, DateTime.utc(2026, 12, 1, 21, 45));
    expect(shown.single.title, '기내 휴식');
    expect(shown.single.inflightMissedNight, isTrue);
    expect(shown.single.detail, contains('크루 배정에 따르고'));
    expect(shown.single.detail, contains('생체시계 밤과 겹치지 않아요.'));
  });

  test('return bunk removes the return inflight event from the plan', () {
    final schedule = xx000Layover();
    final withoutBunk = buildGuideEvents(
      schedule,
      lifestyle: JetlagLifestyle.hybrid,
    ).where((event) => event.kind == GuideEventKind.inflight);
    expect(withoutBunk, hasLength(1));
    expect(withoutBunk.single.startUtc, DateTime.utc(2026, 12, 1, 20, 15));
    expect(withoutBunk.single.endUtc, DateTime.utc(2026, 12, 1, 20, 30));
    expect(withoutBunk.single.inflightMissedNight, isFalse);

    final withBunk = buildGuideEvents(
      schedule,
      lifestyle: JetlagLifestyle.hybrid,
      bunkShift: BunkShift.p2EarlyRest,
    ).where((event) => event.kind == GuideEventKind.inflight);
    expect(withBunk, isEmpty);
  });

  testWidgets('bunk card shows assigned-rest ∩ night when a shift is selected', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final schedule = xx000Layover();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: BunkSelectionCard(
            schedule: schedule,
            role: JetlagCrewRole.flightOps,
            selected: BunkShift.p2EarlyRest,
            onSelected: (_) {},
            lifestyle: JetlagLifestyle.hybrid,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('bunk-body-clock-headline')), findsOneWidget);
    expect(find.byKey(const ValueKey('bunk-body-clock')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bunk-body-clock-supplement')),
      findsOneWidget,
    );
    // Hybrid return: P2 assigned rest misses the shifted night.
    expect(find.text('생체시계 밤과 겹치지 않아요'), findsOneWidget);
    expect(find.textContaining('생체시계 밤'), findsWidgets);
    expect(find.textContaining('(SFO)'), findsWidgets);
    expect(find.textContaining('04:30–12:30 (SFO)'), findsOneWidget);
    expect(find.textContaining('21:30–05:30'), findsOneWidget);
    expect(find.textContaining('짧게 겹쳐요'), findsNothing);
    expect(find.textContaining('이륙 직후'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(
      JetlagTheme.accentFor(GuideEventKind.inflight),
      isNot(JetlagTheme.sleep),
    );
  });

  testWidgets(
    'AMS 21:15 kstAnchor P2 bunk card shows short overlap at 360dp',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final schedule = amsLayover();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: BunkSelectionCard(
              schedule: schedule,
              role: JetlagCrewRole.flightOps,
              selected: BunkShift.p2EarlyRest,
              onSelected: (_) {},
              lifestyle: JetlagLifestyle.kstAnchor,
              settings: UserSettings.defaults,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final headline = find.byKey(const ValueKey('bunk-body-clock-headline'));
      final line = find.byKey(const ValueKey('bunk-body-clock'));
      final supplement = find.byKey(
        const ValueKey('bunk-body-clock-supplement'),
      );
      expect(headline, findsOneWidget);
      expect(line, findsOneWidget);
      expect(supplement, findsOneWidget);

      expect(find.text('짧게 겹쳐요'), findsOneWidget);
      expect(find.textContaining('겹치지 않아요'), findsNothing);

      final lineText = tester.widget<Text>(line).data!;
      expect(lineText, contains('22:45–23:00 (AMS)'));
      expect(lineText, contains('06:45–07:00'));
      expect(lineText, contains('겹치는 시간'));
      expect(tester.widget<Text>(line).maxLines, 1);
      expect(tester.getSize(line).height, lessThan(24));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'AMS 21:15 kstAnchor P1 bunk card shows full night on miss at 360dp',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final schedule = amsLayover();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: BunkSelectionCard(
              schedule: schedule,
              role: JetlagCrewRole.flightOps,
              selected: BunkShift.p1LateRest,
              onSelected: (_) {},
              lifestyle: JetlagLifestyle.kstAnchor,
              settings: UserSettings.defaults,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('생체시계 밤과 겹치지 않아요'), findsOneWidget);
      expect(find.text('짧게 겹쳐요'), findsNothing);

      final lineText =
          tester.widget<Text>(find.byKey(const ValueKey('bunk-body-clock'))).data!;
      expect(lineText, contains('15:00–23:00 (AMS)'));
      expect(lineText, contains('23:00–07:00'));
      expect(lineText, contains('생체시계 밤'));
      expect(tester.widget<Text>(find.byKey(const ValueKey('bunk-body-clock'))).maxLines, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'AMS 21:15 bunk card with 21:00–05:00 settings shows the full night',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const earlyNight = UserSettings(
        defaultBedTime: DayTime(hour: 21, minute: 0),
        defaultWakeTime: DayTime(hour: 5, minute: 0),
      );
      final schedule = amsLayover();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: BunkSelectionCard(
              schedule: schedule,
              role: JetlagCrewRole.flightOps,
              selected: BunkShift.p1LateRest,
              onSelected: (_) {},
              lifestyle: JetlagLifestyle.kstAnchor,
              settings: earlyNight,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('생체시계 밤과 겹치지 않아요'), findsOneWidget);
      expect(find.text('짧게 겹쳐요'), findsNothing);

      final lineText =
          tester.widget<Text>(find.byKey(const ValueKey('bunk-body-clock'))).data!;
      expect(lineText, contains('13:00–21:00 (AMS)'));
      expect(lineText, contains('21:00–05:00'));
      expect(lineText, contains('생체시계 밤'));
      expect(lineText.contains('가까운 시간'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  test('XX000/XX001 bunkBodyClockOverlap branches differ for P1 and P2', () {
    final outbound = JetlagScheduleSnapshot(
      stationLabel: 'SFO',
      originLabel: 'ICN',
      localTimeZone: home,
      referenceTimeZone: home,
      staUtc: outboundSta,
      stdUtc: outboundStd,
      flightNumber: 'XX000',
      blockMinutes: 11 * 60,
    );
    final outboundP1 = bunkBodyClockOverlap(
      schedule: outbound,
      shift: BunkShift.p1LateRest,
      lifestyle: JetlagLifestyle.kstAnchor,
      originZone: home,
      destinationZone: sfo,
      homeZone: home,
    )!;
    final outboundP2 = bunkBodyClockOverlap(
      schedule: outbound,
      shift: BunkShift.p2EarlyRest,
      lifestyle: JetlagLifestyle.kstAnchor,
      originZone: home,
      destinationZone: sfo,
      homeZone: home,
    )!;

    expect(outboundP1.overlap, const Duration(hours: 1, minutes: 35));
    expect(outboundP1.shortOverlap, isFalse);
    expect(outboundP1.missedNight, isFalse);
    expect(
      outboundP1.headline,
      '배정 휴식이 생체시계 밤과 1시간 35분 겹쳐요',
    );
    expect(outboundP1.lineStartUtc, DateTime.utc(2026, 11, 29, 14));
    expect(outboundP1.lineEndUtc, DateTime.utc(2026, 11, 29, 15, 35));
    expect(outboundP2.missedNight, isTrue);
    expect(outboundP2.headline, '생체시계 밤과 겹치지 않아요');
    expect(outboundP1.headline, isNot(outboundP2.headline));

    final returning = xx000Layover();
    final returnP1 = bunkBodyClockOverlap(
      schedule: returning,
      shift: BunkShift.p1LateRest,
      lifestyle: JetlagLifestyle.kstAnchor,
      originZone: sfo,
      destinationZone: home,
      homeZone: home,
    )!;
    final returnP2 = bunkBodyClockOverlap(
      schedule: returning,
      shift: BunkShift.p2EarlyRest,
      lifestyle: JetlagLifestyle.kstAnchor,
      originZone: sfo,
      destinationZone: home,
      homeZone: home,
    )!;

    expect(returnP2.shortOverlap, isTrue);
    expect(returnP2.missedNight, isFalse);
    expect(returnP2.overlap, const Duration(minutes: 45));
    expect(returnP2.headline, '짧게 겹쳐요');
    expect(returnP1.missedNight, isTrue);
    expect(returnP1.headline, '생체시계 밤과 겹치지 않아요');
    expect(returnP1.headline, isNot(returnP2.headline));
  });

  testWidgets('AMS bunk card swaps headline when P2 becomes P1', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final schedule = amsLayover();
    BunkShift selected = BunkShift.p2EarlyRest;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return BunkSelectionCard(
                schedule: schedule,
                role: JetlagCrewRole.flightOps,
                selected: selected,
                onSelected: (next) => setState(() => selected = next),
                lifestyle: JetlagLifestyle.kstAnchor,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('짧게 겹쳐요'), findsOneWidget);
    expect(find.textContaining('22:45–23:00 (AMS)'), findsOneWidget);

    await tester.tap(find.text('P1 후반휴식'));
    await tester.pumpAndSettle();

    expect(find.text('생체시계 밤과 겹치지 않아요'), findsOneWidget);
    expect(find.text('짧게 겹쳐요'), findsNothing);
    expect(find.textContaining('15:00–23:00 (AMS)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('AMS bunk assigned rest matches P2 short and P1 miss expectations', () {
    final schedule = amsLayover();
    final p2 = bunkBodyClockOverlap(
      schedule: schedule,
      shift: BunkShift.p2EarlyRest,
      lifestyle: JetlagLifestyle.kstAnchor,
    )!;
    final p1 = bunkBodyClockOverlap(
      schedule: schedule,
      shift: BunkShift.p1LateRest,
      lifestyle: JetlagLifestyle.kstAnchor,
    )!;

    final p2Rest = bunkAssignedRest(schedule, BunkShift.p2EarlyRest);
    expect(p2Rest.startUtc, DateTime.utc(2026, 11, 28, 21, 45));
    expect(p2Rest.endUtc, DateTime.utc(2026, 11, 29, 1, 45));
    expect(formatHm(p2Rest.startUtc, ams), '22:45');
    expect(formatHm(p2Rest.endUtc, ams), '02:45');

    expect(p2.overlap, const Duration(minutes: 15));
    expect(p2.shortOverlap, isTrue);
    expect(p2.headline, '짧게 겹쳐요');
    expect(formatHm(p2.lineStartUtc, ams), '22:45');
    expect(formatHm(p2.lineEndUtc, ams), '23:00');
    expect(formatHm(p2.lineStartUtc, home), '06:45');
    expect(formatHm(p2.lineEndUtc, home), '07:00');
    expect(p2.headline.contains('겹치지 않아요'), isFalse);

    final p1Rest = bunkAssignedRest(schedule, BunkShift.p1LateRest);
    expect(p1Rest.startUtc, DateTime.utc(2026, 11, 29, 1, 45));
    expect(p1Rest.endUtc, DateTime.utc(2026, 11, 29, 5, 15));
    expect(p1.missedNight, isTrue);
    expect(p1.headline, '생체시계 밤과 겹치지 않아요');
    expect(formatHm(p1.lineStartUtc, ams), '15:00');
    expect(formatHm(p1.lineEndUtc, ams), '23:00');
    expect(formatHm(p1.lineStartUtc, home), '23:00');
    expect(formatHm(p1.lineEndUtc, home), '07:00');
    expect(p1.headline.contains('짧게'), isFalse);
  });
}
