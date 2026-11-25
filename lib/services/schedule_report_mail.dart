import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Replace this when the report inbox is decided.
const kScheduleReportEmail = 'dev@jetlagguide.app';

const kScheduleReportSubject = '[JetLagGuide] 타 항공사 스케줄 양식 제보';

const kScheduleReportPrompt = '지원되지 않는 항공사인가요? 스케줄 스크린샷을 보내주시면 분석 엔진에 추가하겠습니다.';

/// Mailto link with the report subject already filled in.
///
/// Kept as a string because [Uri.toString] rewrites spaces in the query as
/// `+`, and some mail apps leave those plus signs in the subject.
String scheduleReportLink({String email = kScheduleReportEmail}) {
  final subject = Uri.encodeComponent(kScheduleReportSubject);
  return 'mailto:$email?subject=$subject';
}

Future<bool> openScheduleReport() async {
  try {
    return await launchUrlString(
      scheduleReportLink(),
      mode: LaunchMode.externalApplication,
    );
  } catch (error, stack) {
    debugPrint('Jet Lag Guide: report mail failed: $error\n$stack');
    return false;
  }
}
