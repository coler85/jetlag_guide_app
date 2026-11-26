import 'package:flutter/material.dart';

import '../logic/jetlag_clock.dart';
import '../models/flight_leg.dart';
import '../models/flight_schedule_input.dart';
import '../models/jetlag_schedule.dart';
import '../services/ke_roster_gateway.dart';
import '../services/schedule_file_picker.dart';
import '../services/schedule_parser_service.dart';
import '../services/schedule_report_mail.dart';
import '../state/jetlag_guide_controller.dart';
import '../theme/jetlag_theme.dart';
import '../widgets/manual_schedule_form.dart';
import '../widgets/pickup_lead_line.dart';
import '../widgets/schedule_action_card.dart';

/// Hides the image/PDF upload card until file recognition is ready.
/// The picker and parser stay wired for when this is turned back on.
const kShowScheduleUpload = false;

enum _ScheduleSource { image, document }

/// Tab that turns a file, a roster link, or a typed layover into a guide.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.controller,
    required this.onSchedule,
    required this.roster,
    this.parser = const ScheduleParserService(),
    this.files = const ScheduleFilePicker(),
  });

  static const parseRouteName = 'schedule-parse';

  static const recognitionPending = '아직 파일 자동 인식은 준비 중입니다. 직접 입력으로 넣어 주세요.';

  final JetlagGuideController controller;
  final ValueChanged<FlightScheduleInput> onSchedule;
  final KeRosterGateway roster;
  final ScheduleParserService parser;
  final ScheduleFilePicker files;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          key: const ValueKey('jetlag-schedule-page'),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (controller.hasSchedule) ...[
                    _CurrentLayover(
                      key: ValueKey(
                        _headerIdentity(
                          controller.journey,
                          controller.schedule,
                        ),
                      ),
                      journey: controller.journey,
                      schedule: controller.schedule,
                      now: controller.now(),
                      onEditPickup: _editPickup,
                      onEdit: () => _openManualForm(edit: true),
                    ),
                    const SizedBox(height: 22),
                  ],
                  Text(
                    controller.hasSchedule ? '다른 일정 가져오기' : '일정을 가져와 주세요',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: JetlagTheme.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '파일 또는 직접 입력으로 시차 가이드를 만듭니다.',
                    style: JetlagTheme.caption,
                  ),
                  const SizedBox(height: 18),
                  if (kShowScheduleUpload)
                    ScheduleActionCard(
                      key: const ValueKey('schedule-action-file'),
                      emoji: '📄',
                      title: '스케줄 이미지/PDF 업로드',
                      subtitle: '자동 분석',
                      accent: JetlagTheme.duty,
                      onTap: _pickFile,
                    ),
                  if (kShowRosterImport)
                    ScheduleActionCard(
                      key: const ValueKey('schedule-action-roster'),
                      emoji: '✈️',
                      title: 'KE Roster에서 스케줄 불러오기',
                      subtitle: '딥링크 연동',
                      accent: JetlagTheme.meal,
                      onTap: _openRoster,
                    ),
                  ScheduleActionCard(
                    key: const ValueKey('schedule-action-manual'),
                    emoji: '✍️',
                    title: '수동으로 스케줄 입력하기',
                    subtitle: '가는 편·오는 편, 쇼업, 현지 픽업',
                    accent: JetlagTheme.sleep,
                    onTap: _enterManually,
                  ),
                  if (kShowReportMail)
                    ScheduleActionCard(
                      key: const ValueKey('schedule-action-report'),
                      emoji: '💡',
                      title: '미지원 항공사 스케줄 양식 제보하기',
                      subtitle: '스크린샷을 보내 분석 엔진에 추가합니다',
                      accent: JetlagTheme.light,
                      onTap: _reportFormat,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickFile() async {
    if (_busy) return;
    final source = await showModalBottomSheet<_ScheduleSource>(
      context: context,
      showDragHandle: true,
      backgroundColor: JetlagTheme.card,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('분석할 파일', style: JetlagTheme.title),
                  subtitle: Text(
                    '이미지 또는 PDF를 고릅니다.',
                    style: JetlagTheme.caption,
                  ),
                ),
                ListTile(
                  key: const ValueKey('schedule-source-image'),
                  leading: const Icon(
                    Icons.photo_outlined,
                    color: JetlagTheme.duty,
                  ),
                  title: const Text('이미지 선택'),
                  subtitle: const Text('사진 보관함'),
                  onTap: () => Navigator.pop(context, _ScheduleSource.image),
                ),
                ListTile(
                  key: const ValueKey('schedule-source-file'),
                  leading: const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: JetlagTheme.duty,
                  ),
                  title: const Text('PDF 또는 이미지 파일'),
                  onTap: () => Navigator.pop(context, _ScheduleSource.document),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (source == null || !mounted) return;
    try {
      final file = switch (source) {
        _ScheduleSource.image => await widget.files.pickImage(),
        _ScheduleSource.document => await widget.files.pickDocument(),
      };
      if (file == null || !mounted) return;
      await _parse(file);
    } catch (error, stack) {
      debugPrint('schedule file pick failed: $error\n$stack');
      if (mounted) _note('파일을 열지 못했습니다.');
    }
  }

  Future<void> _parse(ScheduleFileRef file) async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      routeSettings: const RouteSettings(name: ScheduleScreen.parseRouteName),
      builder: (_) => const _ParseProgressDialog(),
    );
    try {
      final input = await widget.parser.parseFile(file);
      if (!mounted || !_closeParseDialog()) return;
      if (input == null) {
        await _openManualForm(notice: ScheduleScreen.recognitionPending);
        return;
      }
      widget.onSchedule(input);
    } catch (error, stack) {
      debugPrint('schedule parse failed: $error\n$stack');
      if (!mounted) return;
      if (_closeParseDialog()) _note('일정을 분석하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pops the parse dialog when it is still the route we opened.
  /// A deep link can dismiss it first; then the parse result is discarded.
  bool _closeParseDialog() {
    var open = false;
    Navigator.of(context).popUntil((route) {
      if (route.settings.name == ScheduleScreen.parseRouteName) open = true;
      return route.settings.name != ScheduleScreen.parseRouteName;
    });
    return open;
  }

  Future<void> _openRoster() async {
    if (_busy) return;
    final result = await widget.roster.open();
    if (!mounted) return;
    final message = switch (result) {
      KeRosterOpenResult.opened => 'KE Roster를 열었습니다. 스케줄이 도착하면 타임라인으로 이동합니다.',
      KeRosterOpenResult.notInstalled =>
        '이 기기에 KE Roster가 없습니다. 앱이 스케줄을 보내면 여기서 받아 타임라인으로 이동합니다.',
      KeRosterOpenResult.failed =>
        'KE Roster를 열지 못했습니다. 딥링크가 도착하면 타임라인으로 이동합니다.',
    };
    await showDialog<void>(
      context: context,
      routeSettings: const RouteSettings(name: KeRosterGateway.waitRouteName),
      builder: (context) {
        return _RosterWaitDialog(message: message);
      },
    );
  }

  Future<void> _enterManually() async {
    if (_busy) return;
    await _openManualForm();
  }

  Future<void> _openManualForm({String? notice, bool edit = false}) async {
    if (!mounted) return;
    final controller = widget.controller;
    final home = controller.homeBaseTimezone;
    final saved = controller.journey;
    final input = await Navigator.of(context).push<FlightScheduleInput>(
      MaterialPageRoute(
        fullscreenDialog: true,
        settings: const RouteSettings(name: ManualScheduleForm.routeName),
        builder: (_) => ManualScheduleForm(
          timeZone: home,
          referenceTimeZone: home,
          settings: controller.settings,
          role: controller.role,
          initial: edit
              ? saved ??
                    (controller.hasSchedule
                        ? FlightScheduleInput.fromSnapshot(controller.schedule)
                        : null)
              : null,
          notice: notice,
        ),
      ),
    );
    if (!mounted || input == null) return;
    widget.onSchedule(input);
  }

  Future<void> _reportFormat() async {
    if (_busy) return;
    await showDialog<void>(
      context: context,
      builder: (context) => const _ReportFormatDialog(),
    );
  }

  Future<void> _editPickup() async {
    final schedule = widget.controller.schedule;
    final anchor = (schedule.pickupUtc ?? schedule.stdUtc).toUtc();
    final next = await showPickupTimeSheet(
      context: context,
      pickupUtc: anchor,
      departureUtc: schedule.stdUtc,
      iana: schedule.localTimeZone,
    );
    if (next == null || !mounted) return;
    await widget.controller.setPickup(next);
  }

  void _note(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CurrentLayover extends StatefulWidget {
  const _CurrentLayover({
    super.key,
    required this.journey,
    required this.schedule,
    required this.now,
    required this.onEditPickup,
    required this.onEdit,
  });

  final FlightScheduleInput? journey;
  final JetlagScheduleSnapshot schedule;
  final DateTime now;
  final VoidCallback onEditPickup;
  final VoidCallback onEdit;

  @override
  State<_CurrentLayover> createState() => _CurrentLayoverState();
}

class _CurrentLayoverState extends State<_CurrentLayover> {
  late final PageController _pages;
  late List<_HeaderCard> _cards;
  late int _index;

  @override
  void initState() {
    super.initState();
    _cards = _headerCards(widget.journey, widget.schedule);
    _index = _headerIndex(widget.journey, widget.now, _cards.length);
    _pages = PageController(initialPage: _index);
  }

  @override
  void didUpdateWidget(covariant _CurrentLayover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _cards = _headerCards(widget.journey, widget.schedule);
    if (_index >= _cards.length) _index = _cards.length - 1;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: JetlagTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: JetlagTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 132,
              child: PageView(
                key: const ValueKey('schedule-header-page'),
                controller: _pages,
                physics: _cards.length < 2
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: (index) => setState(() => _index = index),
                children: [for (final card in _cards) _cardBody(card)],
              ),
            ),
            if (_cards.length > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _cards.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: DecoratedBox(
                        key: ValueKey(
                          i == _index
                              ? 'schedule-header-dot-$i-on'
                              : 'schedule-header-dot-$i',
                        ),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _index
                              ? JetlagTheme.duty
                              : JetlagTheme.border,
                        ),
                        child: const SizedBox(width: 6, height: 6),
                      ),
                    ),
                ],
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  children: [
                    TextButton(
                      key: const ValueKey('schedule-edit'),
                      onPressed: widget.onEdit,
                      child: const Text('일정 수정'),
                    ),
                    TextButton(
                      onPressed: widget.onEditPickup,
                      child: const Text('픽업 시간 수정'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardBody(_HeaderCard card) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.kicker, style: JetlagTheme.caption),
          const SizedBox(height: 8),
          _route(card.route),
          if (card.flight.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(card.flight, style: JetlagTheme.body),
          ],
          for (final line in card.lines) ...[
            const SizedBox(height: 4),
            Text(line, style: JetlagTheme.caption),
          ],
        ],
      ),
    );
  }

  Widget _route(List<String> codes) {
    return Row(
      children: [
        for (var i = 0; i < codes.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('→', style: JetlagTheme.body),
            ),
          Text(codes[i], style: JetlagTheme.clock),
        ],
      ],
    );
  }
}

class _HeaderCard {
  const _HeaderCard({
    required this.kicker,
    required this.route,
    this.flight = '',
    this.lines = const [],
  });

  final String kicker;
  final List<String> route;
  final String flight;
  final List<String> lines;
}

String _headerIdentity(
  FlightScheduleInput? journey,
  JetlagScheduleSnapshot schedule,
) {
  final out = journey?.outbound;
  final back = journey?.returning;
  return '${out?.origin}|${out?.stdUtc.toIso8601String()}|'
      '${back?.origin}|${back?.stdUtc.toIso8601String()}|${schedule.key}';
}

List<_HeaderCard> _headerCards(
  FlightScheduleInput? journey,
  JetlagScheduleSnapshot schedule,
) {
  final out = journey?.outbound;
  final back = journey?.returning;
  final roundTrip =
      out != null &&
      back != null &&
      out.arrivesAfterDeparture &&
      back.arrivesAfterDeparture;
  if (roundTrip) {
    return [
      _flightCard('가는 편', out),
      _layoverCard(out, back),
      _flightCard('오는 편', back),
    ];
  }
  if (out != null && back == null && out.arrivesAfterDeparture) {
    return [_flightCard('가는 편', out)];
  }
  if (journey != null &&
      journey.returnOnly &&
      journey.returning!.arrivesAfterDeparture) {
    return [_flightCard('오는 편', journey.returning!)];
  }
  return [_legacyCard(schedule)];
}

int _headerIndex(FlightScheduleInput? journey, DateTime now, int count) {
  if (count < 3) return 0;
  final out = journey?.outbound;
  final back = journey?.returning;
  if (out == null || back == null) return 0;
  final instant = now.toUtc();
  if (instant.isBefore(out.staUtc)) return 0;
  if (instant.isBefore(back.stdUtc)) return 1;
  return 2;
}

_HeaderCard _flightCard(String kicker, FlightLeg leg) {
  final originZone = leg.originTimeZone.trim().isEmpty
      ? leg.destinationTimeZone
      : leg.originTimeZone;
  return _HeaderCard(
    kicker: kicker,
    route: [leg.origin, leg.destination],
    flight: leg.flightNumber,
    lines: [
      '출발 ${_localClock(leg.stdUtc, originZone)}',
      '도착 ${_localClock(leg.staUtc, leg.destinationTimeZone)}',
    ],
  );
}

_HeaderCard _layoverCard(FlightLeg outbound, FlightLeg returning) {
  final zone = outbound.destinationTimeZone;
  return _HeaderCard(
    kicker: '레이오버',
    route: [outbound.destination],
    lines: [
      '도착 ${_localClock(outbound.staUtc, zone)}',
      '출발 ${_localClock(returning.stdUtc, zone)}',
    ],
  );
}

_HeaderCard _legacyCard(JetlagScheduleSnapshot schedule) {
  final pickup = schedule.pickupUtc;
  return _HeaderCard(
    kicker: '현재 일정',
    route: [
      if (schedule.originLabel.isNotEmpty) schedule.originLabel,
      schedule.stationLabel,
    ],
    flight: schedule.flightNumber,
    lines: [
      pickup == null
          ? '픽업 미입력'
          : '픽업 ${_placedClock(pickup, schedule.localTimeZone, schedule.referenceTimeZone, schedule.stationLabel)}',
    ],
  );
}

String _localClock(DateTime utc, String zone) {
  final iana = zone.trim();
  if (iana.isEmpty) return '${formatUtcHm(utc)}Z';
  try {
    return '${formatHm(utc, iana)} ${zoneAbbreviation(utc, iana)}';
  } catch (_) {
    return '${formatUtcHm(utc)}Z';
  }
}

String _placedClock(
  DateTime utc,
  String localZone,
  String homeZone,
  String station,
) {
  final local = formatHm(utc, localZone);
  final homeName = zoneAbbreviation(utc, homeZone);
  if (localZone == homeZone) return '$local $homeName';
  final home = formatHm(utc, homeZone);
  return '$local $station · $home $homeName';
}

class _ParseProgressDialog extends StatelessWidget {
  const _ParseProgressDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: const Padding(
          padding: EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 18),
              Text('스케줄을 분석하는 중', style: JetlagTheme.title),
              SizedBox(height: 8),
              Text(
                '출도착과 픽업 시각을 읽고 있습니다.',
                style: JetlagTheme.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RosterWaitDialog extends StatelessWidget {
  const _RosterWaitDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text('✈️', style: TextStyle(fontSize: 22)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('KE Roster 연동', style: JetlagTheme.title),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
              const SizedBox(height: 14),
              Text(message, style: JetlagTheme.body),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportFormatDialog extends StatelessWidget {
  const _ReportFormatDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text('💡', style: TextStyle(fontSize: 22)),
                  SizedBox(width: 8),
                  Expanded(child: Text('미지원 항공사', style: JetlagTheme.title)),
                ],
              ),
              const SizedBox(height: 14),
              const Text(kScheduleReportPrompt, style: JetlagTheme.body),
              const SizedBox(height: 12),
              Text(
                '메일 제목: $kScheduleReportSubject',
                style: JetlagTheme.caption,
              ),
              const SizedBox(height: 4),
              Text(kScheduleReportEmail, style: JetlagTheme.micro),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('닫기'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: () => _send(context),
                    child: const Text('메일 보내기'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send(BuildContext context) async {
    final opened = await openScheduleReport();
    if (!context.mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('메일 앱을 열 수 없습니다.')));
      return;
    }
    Navigator.pop(context);
  }
}
