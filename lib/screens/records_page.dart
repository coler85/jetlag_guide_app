import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/jetlag_clock.dart';
import '../models/crew_log.dart';
import '../models/jetlag_schedule.dart';
import '../notifications/jetlag_alert_channel.dart';
import '../state/jetlag_guide_controller.dart';
import '../theme/jetlag_theme.dart';
import '../widgets/inline_log_chip.dart';
import '../widgets/timezone_picker.dart';
import '../widgets/user_settings_form.dart';

class RecordsPage extends StatelessWidget {
  const RecordsPage({
    super.key,
    required this.controller,
    this.onScheduleCleared,
  });

  final JetlagGuideController controller;
  final VoidCallback? onScheduleCleared;

  @override
  Widget build(BuildContext context) {
    final logs = [...controller.logs]
      ..sort((a, b) => b.atUtc.compareTo(a.atUtc));
    return ListView(
      key: const ValueKey('jetlag-records-page'),
      primary: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: const ValueKey('clear-schedule'),
            onPressed: () {
              unawaited(
                _confirmClearSchedule(context, controller, onScheduleCleared),
              );
            },
            child: const Text('일정 지우기'),
          ),
        ),
        const SizedBox(height: 16),
        const Text('직군', style: JetlagTheme.caption),
        const SizedBox(height: 8),
        SegmentedButton<JetlagCrewRole>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: JetlagCrewRole.flightOps, label: Text('운항')),
            ButtonSegment(value: JetlagCrewRole.cabin, label: Text('객실')),
          ],
          selected: {controller.role},
          onSelectionChanged: (next) {
            if (next.isEmpty) return;
            controller.setRole(next.first);
          },
        ),
        const SizedBox(height: 16),
        const Text('기준 시간대', style: JetlagTheme.caption),
        const SizedBox(height: 8),
        TimezonePicker(
          selected: controller.homeBaseTimezone,
          onChanged: controller.setHomeBaseTimezone,
        ),
        if (controller.homeBaseRecovered)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '저장된 기준 시간대를 읽지 못해 서울(Asia/Seoul)로 되돌렸습니다.',
              style: JetlagTheme.micro,
            ),
          ),
        const SizedBox(height: 16),
        UserSettingsForm(
          settings: controller.settings,
          onChanged: controller.setUserSettings,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('jetlag-alert-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('픽업 알림', style: JetlagTheme.body),
          subtitle: const Text(
            '90분 전 · 채널 ${JetlagAlertChannel.id}',
            key: ValueKey('jetlag-alert-channel'),
            style: JetlagTheme.caption,
          ),
          value: controller.alertsEnabled,
          onChanged: (enabled) {
            final messenger = ScaffoldMessenger.of(context);
            unawaited(() async {
              final ok = await controller.setAlertsEnabled(enabled);
              if (!ok) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('알림 권한이 없어 채널을 켜지 못했습니다')),
                );
              }
            }());
          },
        ),
        const SizedBox(height: 8),
        const Text('수면 기록', style: JetlagTheme.caption),
        const SizedBox(height: 8),
        if (controller.sleepLogs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('입력한 수면이 없습니다', style: JetlagTheme.body),
          )
        else
          for (final sleep in controller.sleepLogs.reversed) ...[
            InlineLogChip(
              log: CrewLog(
                id: sleep.id,
                atUtc: sleep.startUtc,
                kind: CrewLogKind.sleep,
                scheduleKey: sleep.scheduleKey,
              ),
              clock: controller.hasSchedule
                  ? formatRange(
                      sleep.startUtc,
                      sleep.endUtc,
                      controller.schedule.localTimeZone,
                    )
                  : formatRange(sleep.startUtc, sleep.endUtc, 'UTC'),
              onDismiss: () => controller.removeSleepLog(sleep.id),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 8),
        const Text('기록', style: JetlagTheme.caption),
        const SizedBox(height: 8),
        if (logs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('아직 기록이 없습니다', style: JetlagTheme.body),
          )
        else
          for (final log in logs) ...[
            InlineLogChip(
              log: log,
              clock: formatHm(log.atUtc, controller.schedule.localTimeZone),
              onDismiss: () => controller.removeLog(log.id),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 8),
        const Text(JetlagTheme.disclaimer, style: JetlagTheme.micro),
      ],
    );
  }
}

Future<void> _confirmClearSchedule(
  BuildContext context,
  JetlagGuideController controller,
  VoidCallback? onCleared,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        key: const ValueKey('clear-schedule-dialog'),
        title: const Text('일정 지우기'),
        content: const Text('이 일정을 지우고 안내 화면으로 돌아갑니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('clear-schedule-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('지우기'),
          ),
        ],
      );
    },
  );
  if (confirmed != true || !context.mounted) return;
  await controller.clearSchedule();
  if (!context.mounted) return;
  onCleared?.call();
}
