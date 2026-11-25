import 'package:flutter/material.dart';

import '../logic/jetlag_clock.dart';
import '../models/flight_schedule_input.dart';
import '../models/jetlag_schedule.dart';
import '../services/ke_roster_gateway.dart';
import '../services/schedule_file_picker.dart';
import '../services/schedule_parser_service.dart';
import '../services/schedule_report_mail.dart';
import '../state/jetlag_guide_controller.dart';
import '../theme/jetlag_theme.dart';
import '../widgets/manual_schedule_form.dart';
import '../widgets/schedule_action_card.dart';
import '../widgets/wheel_time_picker.dart';

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
                      schedule: controller.schedule,
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
                    '파일, KE Roster, 또는 직접 입력으로 시차 가이드를 만듭니다.',
                    style: JetlagTheme.caption,
                  ),
                  const SizedBox(height: 18),
                  ScheduleActionCard(
                    key: const ValueKey('schedule-action-file'),
                    emoji: '📄',
                    title: '스케줄 이미지/PDF 업로드',
                    subtitle: '자동 분석',
                    accent: JetlagTheme.duty,
                    onTap: _pickFile,
                  ),
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
    final wall = wallClock(anchor, schedule.localTimeZone);
    final picked = await showWheelTimePicker(
      context: context,
      initial: TimeOfDay(hour: wall.hour, minute: wall.minute),
    );
    if (picked == null) return;
    final next = atWallTime(
      dayAnchorUtc: anchor,
      iana: schedule.localTimeZone,
      hour: picked.hour,
      minute: picked.minute,
    );
    await widget.controller.setPickup(next);
  }

  void _note(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CurrentLayover extends StatelessWidget {
  const _CurrentLayover({
    required this.schedule,
    required this.onEditPickup,
    required this.onEdit,
  });

  final JetlagScheduleSnapshot schedule;
  final VoidCallback onEditPickup;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final pickup = schedule.pickupUtc;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: JetlagTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: JetlagTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('현재 일정', style: JetlagTheme.caption),
            const SizedBox(height: 8),
            Row(
              children: [
                if (schedule.originLabel.isNotEmpty)
                  Text(schedule.originLabel, style: JetlagTheme.clock),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('→', style: JetlagTheme.body),
                ),
                Text(schedule.stationLabel, style: JetlagTheme.clock),
              ],
            ),
            if (schedule.flightNumber.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(schedule.flightNumber, style: JetlagTheme.body),
            ],
            const SizedBox(height: 4),
            Text(
              pickup == null ? '픽업 미입력' : '픽업 ${_clocks(pickup)}',
              style: JetlagTheme.caption,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  TextButton(
                    key: const ValueKey('schedule-edit'),
                    onPressed: onEdit,
                    child: const Text('일정 수정'),
                  ),
                  TextButton(
                    onPressed: onEditPickup,
                    child: const Text('픽업 시간 수정'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _clocks(DateTime utc) {
    final local = formatHm(utc, schedule.localTimeZone);
    final homeZone = zoneAbbreviation(utc, schedule.referenceTimeZone);
    if (schedule.localTimeZone == schedule.referenceTimeZone) {
      return '$local $homeZone';
    }
    final home = formatHm(utc, schedule.referenceTimeZone);
    return '$local ${schedule.stationLabel} · $home $homeZone';
  }
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
