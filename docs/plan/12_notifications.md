# 12단계: 알림 (시계 알람 + 안내 푸시 = bowan10c)

상태: ✅ 구현 완료(커밋 전). 샘플은 XX000/XX001만 쓴다.

## 원래 스펙과 출처
- 이 문서 이전 버전: 기상·픽업을 앱 푸시로 예약. bowan10c에서 기상·웨이크업콜은 **휴대폰 시계 앱 알람**으로 옮기고, 앱 푸시는 카페인·식사·취침 안내만 남긴다.
- `01b_round_trip_input.md` 보완 8 D: 기상은 시계 앱 연동. 위젯·워치 전용 앱(가민 등)은 계속 범위 밖. 안내 푸시는 폰 알림 미러링으로 워치에도 보일 수 있다.
- t160u: 백그라운드에서 정확한 알람을 자동 허용할 수 없다. 스위치 켤 때 시스템 설정 화면을 연다.
- t162u: 가민 워치는 제목만 보이므로 시각을 제목으로 옮긴다.

## 조사 결과 (현재 코드)
- 채널 `jetlag_guide_alerts`(high, sound/vibration), id 범위 71000–71999(로스터와 분리).
- 기상 시각 = 계획 수면(`GuideEventKind.sleep`)의 `endUtc`(`alarmWakeUtc`). 카드 표시는 `sleep_alarm_times.dart`.
- 웨이크업콜 = `schedule.pickupUtc − 1시간`.
- Android `MainActivity`: 딥링크 채널 `jetlag_guide/deep_link` 유지, 시계 알람 채널 `jetlag_guide/clock_alarm` 추가.

## 설계

### A. 시계 앱 알람 (Android만, iOS UI 숨김)
- 대상 두 가지, 버튼 각각:
  1. 계획 기상: 지금 이후 가장 가까운 계획 수면의 `endUtc`(기록한 수면·기내 휴식 제외).
  2. 웨이크업콜: `pickupUtc − 1시간`. pickup이 없으면 버튼·안내 숨김.
- 활성: `whenUtc`가 now 이후이고 now+24시간 이하(이상 아님). `ACTION_SET_ALARM`는 날짜 없이 시·분만 받으므로 24시간을 넘기면 잘못된 날에 울린다.
- 비활성: 버튼은 보이되 누르지 못함. 안내 '24시간 안의 기상만 등록돼요' / '24시간 안의 웨이크업콜만 등록돼요'.
- 시각: 폰 현재 시간대. `clockAlarmDeviceLocal`이 TZDateTime을 native UTC DateTime으로 벗긴 뒤 `DateTime.toLocal()`을 쓴다. (`TZDateTime.toLocal()`은 초기화 후 UTC인 `tz.local`을 써서, 암스테르담 겨울에는 현지보다 1시간 이르게 등록됐다.) 스케줄 현지 존의 시·분을 그대로 넣지 않는다.
- 인텐트: `AlarmClock.ACTION_SET_ALARM`, `EXTRA_HOUR`/`EXTRA_MINUTES`, `EXTRA_MESSAGE`는 '기상' 또는 '웨이크업콜'만, `EXTRA_SKIP_UI=false`.
- MethodChannel `jetlag_guide/clock_alarm`, 메서드 `setAlarm`. 새 패키지 없음. `ActivityNotFoundException`은 에러로 돌려 Dart에서 `debugPrint`.
- 매니페스트: `com.android.alarm.permission.SET_ALARM`, `<queries>`에 `SET_ALARM` 인텐트. `USE_EXACT_ALARM` 없음.
- 순수 함수: `lib/notifications/clock_alarm_plan.dart`. 런처: `ClockAlarmLauncher`(Android / iOS 미지원 / 테스트 가짜).
- UI: 기록 화면 '시계 알람' 섹션(keys `jetlag-clock-wake`, `jetlag-clock-wakeup-call`). 가이드 타임라인은 다음 24h 안 기상 수면 카드에만 작은 '시계 알람 등록'(옵셔널 콜백, 기본 null → 기존 레이아웃 테스트 유지).

### B. 앱 푸시 (안내)
- 제거: 기상 푸시(구 스위치·id 71100–71111), 픽업 90분 전 푸시(구 스위치·id 71001). 로드 시 해당 id 취소. 저장 키 `jetlag_guide_wake_alerts_enabled`, `jetlag_guide_alerts_enabled`는 더 이상 읽어서 켜지 않음.
- 유지: '1분 뒤 테스트 알림'(key `jetlag-wake-test`, id 71199). 제목 `테스트 HH:mm · 홈 HH:mm KST`, 본문 `이 알림이 워치에도 보이면 연동이 된 거예요.` 테스트는 정확한 알람 설정 화면을 자동으로 열지 않음.
- 새 푸시 세 종류(종류별 스위치, 기본 꺼짐, 저장 키 따로):
  1. 카페인 마감: `GuideEventKind.caffeine` startUtc 정각. 제목 `카페인 마감 HH:mm · 홈 HH:mm KST`. 본문 `카페인 마감 시각이에요`. id 71200–71211. 키 `jetlag_guide_caffeine_alerts_enabled`. UI key `jetlag-caffeine-switch`.
  2. 식사: `GuideEventKind.meal`만(mealDeadline 제외) startUtc 정각. 제목 `식사 HH:mm · 홈 HH:mm KST`. 본문 `식사 시간이에요`. id 71300–71311. 키 `jetlag_guide_meal_alerts_enabled`. UI key `jetlag-meal-switch`.
  3. 취침: 계획 수면 start − 30분. 제목의 시각은 취침(수면 시작). 예: 22:00 취침 → 21:30 발화, 제목 `곧 취침 22:00 · 홈 ... KST`. 본문 `곧 취침이에요`. 이미 30분 안이면 건너뜀. id 71400–71411. 키 `jetlag_guide_bed_alerts_enabled`. UI key `jetlag-bed-switch`.
- 대상은 지금 이후만, 종류별 가까운 순 최대 12건(테스트 포함 37 이하, iOS 64 한도 여유).
- 채널: 기존 `jetlag_guide_alerts`만 사용. 기상 전용 채널은 새로 예약하지 않음(이미 만든 채널 삭제는 불필요).
- 권한 흐름(bowan10b와 동일):
  - 알림 권한 거부 → 그 스위치는 꺼짐·저장 안 함.
  - 허용 → 스위치 켜고 저장·먼저 예약 → 정확한 알람이 아직이면 `_lock` 밖에서 설정 화면. 거부해도 스위치는 켜진 채 inexact.
  - 어느 스위치든 켜져 있고 `exactAlarmsAllowed==false`이면 회색 안내(key `jetlag-exact-hint`), 탭하면 설정. 별도 버튼 없음.
  - resumed에서 exact 값이 바뀔 때만 켜져 있는 종류를 재예약(서명 클리어).
- 순수 함수: `lib/notifications/guide_alert_plan.dart`. 서명 비교로 재예약. `_publish()` 이후 `unawaited` 동기화. 일정 삭제·스위치 off 시 해당 대역 취소.
- 금지어: 알림 제목/본문/시계 알람 메시지에 의학 용어(권장·치료·처방·진단·효과)·항공사명·편명·개인정보 없음. DateTime 비교는 `isAtSameMomentAs`.

### Android 권한
- `POST_NOTIFICATIONS`(13+), `VIBRATE`, `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`, `SET_ALARM`.
- 수신기: `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`.
- `USE_EXACT_ALARM` 없음.

### iOS
- 알림 권한(alert·sound) 요청. 시계 알람 UI 전체 숨김. Time Sensitive entitlement 없음.

## 구현 메모 (커밋 전)
- 파일: `AndroidManifest.xml`, `MainActivity.kt`, `lib/notifications/*`, `lib/main.dart`, `lib/state/jetlag_guide_controller.dart`, `lib/screens/records_page.dart`, `lib/screens/timeline_page.dart`, `lib/widgets/guide_event_card.dart`, `lib/widgets/sleep_alarm_times.dart`, `lib/widgets/sticky_timeline.dart`, `test/wake_alert_test.dart` 등, `docs/plan/12_notifications.md`, `01b`, `00_OVERVIEW`.
- 컨트롤러: `caffeineAlertsEnabled` / `mealAlertsEnabled` / `bedAlertsEnabled`, `registerClockAlarm`, `nextClockWake` / `nextWakeupCall`, `exactAlarmsAllowed`, `onAppResumed()`.
- UserSettingsForm은 건드리지 않음. 새 패키지·버전·roster_app 변경 없음.
