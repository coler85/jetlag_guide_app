import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../logic/jetlag_clock.dart';
import '../models/crew_log.dart';
import '../models/jetlag_schedule.dart';
import '../notifications/clock_alarm_plan.dart';
import '../state/jetlag_guide_controller.dart';
import '../theme/jetlag_theme.dart';
import '../widgets/inline_log_chip.dart';
import '../widgets/timezone_picker.dart';
import '../widgets/user_settings_form.dart';
import 'guide_rules_screen.dart';

class RecordsPage extends StatelessWidget {
  const RecordsPage({
    super.key,
    required this.controller,
    this.onScheduleCleared,
  });

  final JetlagGuideController controller;
  final VoidCallback? onScheduleCleared;

  bool get _showClockAlarm {
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.android;
  }

  @override
  Widget build(BuildContext context) {
    final logs = [...controller.logs]
      ..sort((a, b) => b.atUtc.compareTo(a.atUtc));
    return Stack(
      children: [
        ListView(
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
                    _confirmClearSchedule(
                      context,
                      controller,
                      onScheduleCleared,
                    ),
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
                ButtonSegment(
                  value: JetlagCrewRole.flightOps,
                  label: Text('운항'),
                ),
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
              key: const ValueKey('jetlag-caffeine-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('카페인 마감', style: JetlagTheme.body),
              subtitle: const Text('정각', style: JetlagTheme.caption),
              value: controller.caffeineAlertsEnabled,
              onChanged: (enabled) {
                final messenger = ScaffoldMessenger.of(context);
                unawaited(() async {
                  final ok = await controller.setCaffeineAlertsEnabled(enabled);
                  if (!ok) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('알림 권한이 없어 채널을 켜지 못했습니다')),
                    );
                  }
                }());
              },
            ),
            SwitchListTile(
              key: const ValueKey('jetlag-meal-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('식사', style: JetlagTheme.body),
              subtitle: const Text('정각', style: JetlagTheme.caption),
              value: controller.mealAlertsEnabled,
              onChanged: (enabled) {
                final messenger = ScaffoldMessenger.of(context);
                unawaited(() async {
                  final ok = await controller.setMealAlertsEnabled(enabled);
                  if (!ok) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('알림 권한이 없어 채널을 켜지 못했습니다')),
                    );
                  }
                }());
              },
            ),
            SwitchListTile(
              key: const ValueKey('jetlag-bed-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('취침', style: JetlagTheme.body),
              subtitle: const Text('30분 전', style: JetlagTheme.caption),
              value: controller.bedAlertsEnabled,
              onChanged: (enabled) {
                final messenger = ScaffoldMessenger.of(context);
                unawaited(() async {
                  final ok = await controller.setBedAlertsEnabled(enabled);
                  if (!ok) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('알림 권한이 없어 채널을 켜지 못했습니다')),
                    );
                  }
                }());
              },
            ),
            _TestAlertActions(controller: controller),
            if (controller.anyGuideAlertsEnabled &&
                controller.exactAlarmsAllowed == false)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  key: const ValueKey('jetlag-exact-hint'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(controller.requestExactAlarm()),
                  child: const Text(
                    '정확한 알람을 허용하면 제시간에 울려요',
                    style: JetlagTheme.caption,
                  ),
                ),
              ),
            if (_showClockAlarm && controller.hasSchedule) ...[
              const SizedBox(height: 8),
              const Text('시계 알람', style: JetlagTheme.caption),
              const SizedBox(height: 4),
              const Text(
                '휴대폰 시계 앱에 등록합니다.',
                style: JetlagTheme.micro,
              ),
              const SizedBox(height: 8),
              _ClockAlarmRow(
                title: '기상',
                plan: controller.nextClockWake,
                buttonKey: const ValueKey('jetlag-clock-wake'),
                inactiveHint: '24시간 안의 기상만 등록돼요',
                localIana: controller.schedule.localTimeZone,
                localTag: controller.schedule.stationLabel,
                onRegister: (plan) {
                  unawaited(
                    controller.registerClockAlarm(
                      whenUtc: plan.whenUtc,
                      message: plan.message,
                    ),
                  );
                },
              ),
              if (controller.nextWakeupCall != null)
                _ClockAlarmRow(
                  title: '웨이크업콜',
                  plan: controller.nextWakeupCall,
                  buttonKey: const ValueKey('jetlag-clock-wakeup-call'),
                  inactiveHint: '24시간 안의 웨이크업콜만 등록돼요',
                  localIana: controller.schedule.localTimeZone,
                  localTag: controller.schedule.stationLabel,
                  onRegister: (plan) {
                    unawaited(
                      controller.registerClockAlarm(
                        whenUtc: plan.whenUtc,
                        message: plan.message,
                      ),
                    );
                  },
                ),
            ],
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
            const SizedBox(height: 8),
            ListTile(
              key: const ValueKey('guide-rules-entry'),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                GuideRulesScreen.entryLabel,
                style: JetlagTheme.body,
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: JetlagTheme.textSecondary,
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) {
                        return GuideRulesScreen(
                          settings: controller.settings,
                          homeBaseTimezone: controller.homeBaseTimezone,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        _AppResumeBinder(controller: controller),
      ],
    );
  }
}

class _ClockAlarmRow extends StatelessWidget {
  const _ClockAlarmRow({
    required this.title,
    required this.plan,
    required this.buttonKey,
    required this.inactiveHint,
    required this.localIana,
    required this.localTag,
    required this.onRegister,
  });

  final String title;
  final ClockAlarmPlan? plan;
  final Key buttonKey;
  final String inactiveHint;
  final String localIana;
  final String localTag;
  final void Function(ClockAlarmPlan plan) onRegister;

  @override
  Widget build(BuildContext context) {
    final current = plan;
    final timeLabel = current == null
        ? '없음'
        : formatAlarmLocal(current.whenUtc, localIana, localTag);
    final active = current?.active == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: JetlagTheme.body),
          const SizedBox(height: 2),
          Text(timeLabel, style: JetlagTheme.caption),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: buttonKey,
              onPressed: active && current != null
                  ? () => onRegister(current)
                  : null,
              child: const Text('시계 알람 등록'),
            ),
          ),
          if (current != null && !active)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                inactiveHint,
                style: JetlagTheme.micro.copyWith(
                  color: JetlagTheme.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppResumeBinder extends StatefulWidget {
  const _AppResumeBinder({required this.controller});

  final JetlagGuideController controller;

  @override
  State<_AppResumeBinder> createState() => _AppResumeBinderState();
}

class _AppResumeBinderState extends State<_AppResumeBinder>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.controller.refreshExactAlarmPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.onAppResumed());
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _TestAlertActions extends StatelessWidget {
  const _TestAlertActions({required this.controller});

  final JetlagGuideController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          key: const ValueKey('jetlag-wake-test'),
          onPressed: () {
            final messenger = ScaffoldMessenger.of(context);
            unawaited(() async {
              final ok = await controller.scheduleTestAlert();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    ok ? '1분 뒤에 테스트 알림이 울립니다' : '알림 권한이 없어 테스트 알림을 예약하지 못했습니다',
                  ),
                ),
              );
            }());
          },
          child: const Text('1분 뒤 테스트 알림'),
        ),
      ),
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
