import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/logic/home_base_timezone.dart';
import 'package:jetlag_guide_app/logic/jetlag_clock.dart';
import 'package:jetlag_guide_app/state/jetlag_state.dart';
import 'package:jetlag_guide_app/theme/jetlag_theme.dart';
import 'package:jetlag_guide_app/widgets/timezone_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(ensureJetlagTimeZones);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('search finds Amsterdam by city text and by airport code', () {
    final byCity = timezoneSearch('amster').all.map((zone) => zone.id);
    final byCode = timezoneSearch('AMS').all.map((zone) => zone.id);
    final byLowerCode = timezoneSearch('ams').all.map((zone) => zone.id);

    expect(byCity, contains('Europe/Amsterdam'));
    expect(byCode, contains('Europe/Amsterdam'));
    expect(byLowerCode, contains('Europe/Amsterdam'));
  });

  test('shortcuts stay first and keep their Korean names', () {
    final result = timezoneSearch('');
    expect(result.favorites.map((zone) => zone.id), [
      for (final zone in kHomeBaseZones) zone.id,
    ]);
    expect(result.favorites.first.title, '서울');
    expect(result.others, isNotEmpty);
    expect(
      result.favorites.map((zone) => zone.id),
      isNot(contains('Europe/Amsterdam')),
    );
    expect(result.others.map((zone) => zone.id), contains('Europe/Amsterdam'));
  });

  test('offset follows daylight saving', () {
    expect(
      timezoneOffsetLabel('Europe/Amsterdam', at: DateTime.utc(2026, 7, 1, 12)),
      'UTC+2',
    );
    expect(
      timezoneOffsetLabel(
        'Europe/Amsterdam',
        at: DateTime.utc(2026, 11, 25, 12),
      ),
      'UTC+1',
    );
    expect(
      timezoneOffsetLabel('America/New_York', at: DateTime.utc(2026, 7, 1, 12)),
      'UTC-4',
    );
    expect(
      timezoneOffsetLabel(
        'America/New_York',
        at: DateTime.utc(2026, 11, 25, 12),
      ),
      'UTC-5',
    );
    expect(
      timezoneOffsetLabel('Asia/Kolkata', at: DateTime.utc(2026, 1, 1)),
      'UTC+5:30',
    );
    expect(timezoneOffsetLabel('Not/AZone'), isEmpty);
  });

  test('a stored home base is kept', () async {
    SharedPreferences.setMockInitialValues({
      JetLagState.preferenceKey: 'Europe/Amsterdam',
    });
    final amsterdam = JetLagState();
    addTearDown(amsterdam.dispose);
    await amsterdam.load();
    expect(amsterdam.homeBaseTimezone, 'Europe/Amsterdam');
    expect(amsterdam.recovered, isFalse);

    SharedPreferences.setMockInitialValues({
      JetLagState.preferenceKey: 'Asia/Seoul',
    });
    final seoul = JetLagState();
    addTearDown(seoul.dispose);
    await seoul.load();
    expect(seoul.homeBaseTimezone, 'Asia/Seoul');
    expect(seoul.recovered, isFalse);
  });

  testWidgets('the picker searches and shows an unknown saved id', (
    tester,
  ) async {
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: JetlagTheme.material,
        home: Scaffold(
          body: TimezonePicker(
            selected: 'Asia/Seoul',
            onChanged: (value) => chosen = value,
          ),
        ),
      ),
    );
    expect(find.textContaining('서울 · Asia/Seoul'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('jetlag-timezone-picker')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('자주 쓰는 시간대'), findsOneWidget);
    expect(find.text('서울'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('timezone-search')),
      'amster',
    );
    await tester.pump();
    expect(find.text('Europe/Amsterdam'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('timezone-search')),
      'AMS',
    );
    await tester.pump();
    expect(find.text('Europe/Amsterdam'), findsWidgets);
    await tester.tap(
      find.byKey(const ValueKey('timezone-option-Europe/Amsterdam')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(chosen, 'Europe/Amsterdam');

    await tester.pumpWidget(
      MaterialApp(
        theme: JetlagTheme.material,
        home: Scaffold(
          body: TimezonePicker(selected: 'Not/AZone', onChanged: _ignore),
        ),
      ),
    );
    expect(find.textContaining('Not/AZone'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('jetlag-timezone-picker')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('현재 선택'), findsOneWidget);
    expect(find.text('Not/AZone'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

void _ignore(String _) {}
