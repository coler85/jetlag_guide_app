import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/main.dart';
import 'package:jetlag_guide_app/screens/timeline_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home opens on three tabs and keeps each tab mounted', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('시차·컨디션'), findsOneWidget);
    expect(find.text('타임라인'), findsOneWidget);
    expect(find.byType(TimelinePage), findsOneWidget);
    expect(find.byKey(const ValueKey('jetlag-bottom-nav')), findsOneWidget);

    await tester.tap(find.text('스케줄'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jetlag-schedule-page')), findsOneWidget);
    expect(find.byType(TimelinePage, skipOffstage: false), findsOneWidget);

    await tester.tap(find.text('기록·설정'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jetlag-records-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('jetlag-schedule-page'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(TimelinePage, skipOffstage: false), findsOneWidget);
  });
}
