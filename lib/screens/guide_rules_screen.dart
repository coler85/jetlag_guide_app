import 'package:flutter/material.dart';

import '../logic/home_base_timezone.dart';
import '../logic/sleep_constants.dart';
import '../models/user_settings.dart';
import '../theme/jetlag_theme.dart';

/// Explains how the guide builds its plan from the crew's own settings.
class GuideRulesScreen extends StatelessWidget {
  const GuideRulesScreen({
    super.key,
    required this.settings,
    required this.homeBaseTimezone,
  });

  final UserSettings settings;
  final String homeBaseTimezone;

  static const entryLabel = '이 가이드는 어떻게 계산하나요';

  @override
  Widget build(BuildContext context) {
    final home = homeClockName(homeBaseTimezone);
    final shift = settings.hybridMaxShiftHours;
    final arrival = _durationLabel(settings.arrivalToSleep);
    final deboard = _durationLabel(settings.arrivalDeboard);
    final transfer = _durationLabel(settings.hotelTransfer);
    final afterHotel = _durationLabel(settings.afterHotelReady);
    final hotelDelay = _durationLabel(settings.hotelArrivalDelay);
    final prep = _durationLabel(settings.prepTime);
    final commute = _durationLabel(settings.commuteTime);
    final target = _durationLabel(settings.sleepTarget);
    final cycle = _durationLabel(kSleepCycle);
    final gap = _durationLabel(kSleepMergeGap);
    final sleepSoon = _durationLabel(kArrivalSleepSoon);
    final mealLead = _durationLabel(kMealLead);
    final napMax = _durationLabel(
      Duration(minutes: kSleepCycle.inMinutes * kNapMaxCycles),
    );
    final napGap = _durationLabel(kNapGapBeforeNight);
    final overnightMin = _durationLabel(kOvernightFlightMin);
    final inflightCap = _durationLabel(kInflightMaxShift);
    final afterTakeoff = _durationLabel(kInflightAfterTakeoff);
    final beforeLanding = _durationLabel(kInflightBeforeLanding);
    final orderLabel = settings.arrivalOrder.label;

    final sections = <_RuleSection>[
      _RuleSection(
        key: const ValueKey('guide-rules-modes'),
        title: '세 가지 모드',
        body:
            '$home 유지는 홈 시간에 맞춰 잠을 둡니다. '
            '하이브리드는 홈 시간에서 최대 $shift시간까지 현지 쪽으로 옮깁니다. '
            '현지 적응은 현지 시간에 맞춥니다.',
      ),
      _RuleSection(
        key: const ValueKey('guide-rules-arrival'),
        title: '도착 후 첫 수면',
        body:
            '도착 후 잠들기까지($arrival)는 하기·입국($deboard) + 호텔 이동($transfer) + '
            '호텔 도착 후 준비($afterHotel)입니다. STA는 램프 도착입니다. '
            '식사는 호텔 도착(하기+이동, $hotelDelay 뒤) 이후에 두고, '
            '수면은 그 뒤 준비까지 기다린 뒤에 둡니다. '
            '착륙 후 도착 후 잠들기까지($arrival)가 지난 뒤부터 '
            '모드 기상 시각까지 잠을 둡니다. '
            '$cycle이 안 되면 다음 취침으로 넘깁니다. '
            '호텔 도착 후 $sleepSoon 안에 시작하는 첫 수면은 도착 직후 수면으로 보고, '
            '도착 후 순서(지금: $orderLabel)로 식사와 수면 사이를 잡습니다. '
            '호텔 도착과 수면 사이가 $mealLead보다 짧으면 '
            '자동·먼저 휴식은 간식 뒤 수면·일어난 뒤 식사로, '
            '먼저 식사는 호텔 도착 식사로 둡니다.',
      ),
      _RuleSection(
        key: const ValueKey('guide-rules-inflight'),
        title: '기내 휴식',
        body:
            '탑승 시점의 생체시계 밤을 목적지 쪽으로 옮겨, '
            '이륙 후 $afterTakeoff부터 착륙 $beforeLanding 전까지와 '
            '겹치는 구간을 현지·홈 시간으로 같이 보여 줍니다. '
            '$home 유지는 옮기지 않습니다. '
            '하이브리드는 지상 이동 상한(최대 $shift시간, 시차 이내)의 절반을 '
            '기내에서 먼저 옮깁니다. '
            '현지 적응은 최대 $inflightCap까지 옮기고, 남은 시차보다 많이 옮기지 않습니다. '
            '출발편은 $home 밤에서 시작하고, 귀국편은 체류 중 모드가 옮긴 밤을 그대로 씁니다. '
            '동쪽 비행은 앞당기고 서쪽 비행은 늦춥니다. '
            '겹치는 시간이 $cycle보다 짧으면 실제 겹친 구간만 보여 주고 '
            '짧은 겹침 안내를 붙입니다. '
            '겹치지 않으면 그 밤에 가까운 비행 구간 $cycle을 보여 주고 '
            '겹치지 않는다는 안내를 붙입니다. '
            '벙크를 고르면 이 시간대가 기내 벙크 카드 안에 붙고 별도 카드는 나오지 않습니다. '
            '실제 휴식은 크루 배정에 따릅니다.',
      ),
      _RuleSection(
        key: const ValueKey('guide-rules-nap'),
        title: '밤샘 비행 뒤 낮잠',
        body:
            '들어오는 편이 모드 밤과 $overnightMin 이상 겹치고 '
            '도착이 모드 낮이면, 도착 후 잠들기까지 뒤에 '
            '최대 $napMax($kNapMaxCycles사이클) 낮잠을 둡니다. '
            '끝은 다음 밤 수면 시작 $napGap 전입니다. '
            '들어오는 편 출발 시각이 없으면 이 낮잠은 두지 않습니다.',
      ),
      _RuleSection(
        key: const ValueKey('guide-rules-departure'),
        title: '출발 전 수면',
        body:
            '픽업이 있으면 픽업에서, 없으면 출발에서 준비($prep)와 이동($commute)을 '
            '빼서 기상 시각을 정합니다. 수면 목표($target) 안에서 $cycle 단위로 채웁니다. '
            '픽업이 밤·새벽일 때만 잡아요. '
            '$home 유지로 저녁($kEveningDepartureStart시 이후)에 서쪽으로 떠날 때는 '
            '출발 전 수면 안내에 한 줄을 덧붙입니다.',
      ),
      _RuleSection(
        key: const ValueKey('guide-rules-gap'),
        title: '수면 간격',
        body: '두 수면 사이가 $gap 미만이면 하나로 합칩니다.',
      ),
      _RuleSection(
        key: const ValueKey('guide-rules-meal-light'),
        title: '식사와 빛',
        body: '식사는 잠들기 1~2시간 전까지 끝나게 두고, 빛 쬐기는 일어난 뒤에만 둡니다.',
      ),
      _RuleSection(
        key: const ValueKey('guide-rules-debt'),
        title: '수면 부채',
        body: '기록한 수면만 수면 목표($target)와 비교합니다.',
      ),
      _RuleSection(
        key: const ValueKey('guide-rules-notice'),
        title: '안내',
        body:
            '이 안내는 참고용 생활 가이드이며 의학적 조언을 대신하지 않습니다. '
            '모든 데이터는 기기 안에만 저장되고 서버로 보내지 않습니다.',
      ),
    ];

    return Scaffold(
      key: const ValueKey('guide-rules-screen'),
      backgroundColor: JetlagTheme.bg,
      appBar: AppBar(title: const Text(entryLabel)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const Text('계획을 이렇게 계산해요', style: JetlagTheme.caption),
          const SizedBox(height: 16),
          for (var index = 0; index < sections.length; index++) ...[
            if (index > 0) const SizedBox(height: 16),
            sections[index],
          ],
        ],
      ),
    );
  }
}

class _RuleSection extends StatelessWidget {
  const _RuleSection({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: JetlagTheme.title),
        const SizedBox(height: 6),
        Text(body, style: JetlagTheme.body),
      ],
    );
  }
}

String _durationLabel(Duration duration) {
  final minutes = duration.inMinutes;
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '$mins분';
  if (mins == 0) return '$hours시간';
  return '$hours시간 $mins분';
}
