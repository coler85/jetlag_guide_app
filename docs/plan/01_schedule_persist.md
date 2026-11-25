# 1단계: 일정 저장, 가짜 분석 결과 막기

상태: ✅ 코드 완료, 미커밋 (2026-11-22) · 2026-11-23 폰 저장·복원 확인

## 목표
사용자가 넣은 일정이 진짜로 쓰이고, 샘플은 사용자가 고를 때만 나온다.

## 할 일
- [x] `adoptSchedule`로 받은 일정을 SharedPreferences에 JSON(UTC ISO)으로 저장
- [x] 앱 시작 시 저장된 일정 복원 → 타임라인 탭으로 열기
- [x] 기록·설정 탭에 '일정 지우기'(확인 다이얼로그)
- [x] 샘플 일정은 저장하지 않고, 볼 때 '샘플 일정' 표시
- [x] `ScheduleParserService.parseFile`의 고정 KE017 결과 제거 → '자동 인식 준비 중' 안내 후 수동 입력 폼
- [x] 테스트: 재시작 복원 / 샘플 미저장 / 파일 → 수동 입력 안내 / 일정 지우기

## 확인 명령
`cd ~/Projects/jetlag_guide_app && flutter analyze && flutter test`

## 보고 기록
- 2026-11-22 21:38 KST Cursor 보고
  - 새 파일: `lib/state/flight_schedule_store.dart`
  - 바꾼 파일: `lib/models/flight_schedule_input.dart`, `lib/state/jetlag_guide_controller.dart`, `lib/services/schedule_parser_service.dart`, `lib/services/schedule_file_picker.dart`, `lib/screens/root_screen.dart`, `lib/screens/timeline_page.dart`, `lib/screens/records_page.dart`, `lib/screens/schedule_screen.dart`, `lib/widgets/manual_schedule_form.dart`, `test/schedule_intake_test.dart`, `test/widget_test.dart`
  - flutter analyze: No issues found / flutter test: 통과 28, 실패 0
  - 확인: 저장은 `adoptSchedule`에서만(샘플 제외), `parseFile`은 null 반환, 코드 경로에 고정 KE017 없음
- 남은 것: 실기기(SM-S948N) 확인, 커밋(11/15–16 스케줄 탭 작업과 함께 파일 이름 지정)
