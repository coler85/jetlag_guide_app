import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/logic/guide_plan.dart';
import 'package:jetlag_guide_app/logic/inflight_rest.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:jetlag_guide_app/models/guide_event.dart';
import 'package:jetlag_guide_app/models/jetlag_schedule.dart';
import 'package:jetlag_guide_app/models/lifestyle.dart';

/// XX000 leaves home and lands at SFO at the sample STA. The block is 11 hours.
/// XX001 leaves that SFO departure and lands 11 hours later.
void main() {
  setUp(ensureJetlagTimeZones);

  const home = 'Asia/Seoul';
  const sfo = 'America/Los_Angeles';

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

  test('XX000 outbound windows follow the home night plus the inflight move', () {
    final anchor = window(outbound: true, lifestyle: JetlagLifestyle.kstAnchor);
    final hybrid = window(outbound: true, lifestyle: JetlagLifestyle.hybrid);
    final local = window(outbound: true, lifestyle: JetlagLifestyle.localAdapt);

    expect(anchor.inflightShift, Duration.zero);
    expect(anchor.shortOverlap, isFalse);
    expect(anchor.startUtc, DateTime.utc(2026, 11, 29, 14));
    expect(anchor.endUtc, DateTime.utc(2026, 11, 29, 16, 35));
    expect(anchor.detail, contains('한국 기준 밤에 가까운 시간대예요.'));
    expect(anchor.detail, contains('실제 휴식은 크루 휴식 배정에 따릅니다.'));
    expect(anchor.detail.contains('짧아요'), isFalse);

    expect(hybrid.inflightShift, const Duration(minutes: -90));
    expect(hybrid.shortOverlap, isFalse);
    expect(hybrid.startUtc, DateTime.utc(2026, 11, 29, 12, 30));
    expect(hybrid.endUtc, DateTime.utc(2026, 11, 29, 16, 35));
    expect(hybrid.detail, contains('1시간 30분'));

    // Home night moved earlier by the 3 hour cap, not the SFO night.
    // A destination-night overlap would start at 07:05Z (23:00 PST).
    expect(local.inflightShift, const Duration(hours: -3));
    expect(local.shortOverlap, isFalse);
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
    expect(anchor.startUtc, DateTime.utc(2026, 12, 1, 20, 15));
    expect(anchor.endUtc, DateTime.utc(2026, 12, 1, 22));
    expect(anchor.detail, contains('한국 기준 밤에 가까운 시간대예요.'));

    expect(hybrid.inflightShift, const Duration(minutes: 90));
    expect(hybrid.shortOverlap, isTrue);
    expect(hybrid.startUtc, DateTime.utc(2026, 12, 1, 20, 15));
    expect(hybrid.endUtc, DateTime.utc(2026, 12, 1, 21, 45));
    expect(hybrid.detail, contains('1시간 30분'));
    expect(hybrid.detail, contains('몸시계 밤과 겹치는 시간이 짧아요.'));

    expect(local.inflightShift, const Duration(hours: 3));
    expect(local.shortOverlap, isTrue);
    expect(local.startUtc, DateTime.utc(2026, 12, 1, 20, 15));
    expect(local.endUtc, DateTime.utc(2026, 12, 1, 21, 45));
    expect(local.detail, contains('3시간'));
    expect(local.detail, contains('몸시계 밤과 겹치는 시간이 짧아요.'));
  });

  test('the XX000 layover timeline shows the return inflight window', () {
    final schedule = JetlagScheduleSnapshot(
      stationLabel: 'SFO',
      originLabel: 'ICN',
      localTimeZone: sfo,
      referenceTimeZone: home,
      staUtc: outboundSta,
      stdUtc: returnStd,
      flightNumber: 'XX000',
      blockMinutes: 11 * 60,
    );
    final shown = buildGuideEvents(
      schedule,
      lifestyle: JetlagLifestyle.localAdapt,
    ).where((event) => event.kind == GuideEventKind.inflight);

    expect(shown, hasLength(1));
    expect(shown.single.startUtc, DateTime.utc(2026, 12, 1, 20, 15));
    expect(shown.single.endUtc, DateTime.utc(2026, 12, 1, 21, 45));
    expect(shown.single.title, '기내 휴식');
    expect(shown.single.detail, contains('크루 휴식 배정에 따릅니다.'));
  });
}
