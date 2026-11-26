import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jetlag_guide_app/main.dart';
import 'package:jetlag_guide_app/screens/guide_rules_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('settings open the guide rules and follow arrival-to-sleep', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('기록·설정'));
    await tester.pumpAndSettle();

    await _openRules(tester);
    expect(find.byKey(const ValueKey('guide-rules-screen')), findsOneWidget);
    expect(find.text(GuideRulesScreen.entryLabel), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('guide-rules-arrival')),
        matching: find.textContaining('도착 후 잠들기까지(2시간 30분)'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('잠들기 1~2시간 전까지'), findsOneWidget);
    _expectNoForbiddenWords(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await _tapArrivalPlus(tester);
    await _tapArrivalPlus(tester);

    await _openRules(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('guide-rules-arrival')),
        matching: find.textContaining('도착 후 잠들기까지(3시간)'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('도착 후 잠들기까지(2시간 30분)'), findsNothing);
    _expectNoForbiddenWords(tester);
  });
}

final _recordsScrollable = find.descendant(
  of: find.byKey(const ValueKey('jetlag-records-page')),
  matching: find.byType(Scrollable),
);

Future<void> _openRules(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('guide-rules-entry')),
    400,
    scrollable: _recordsScrollable,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('guide-rules-entry')));
  await tester.pumpAndSettle();
}

Future<void> _tapArrivalPlus(WidgetTester tester) async {
  final row = find.byKey(const ValueKey('settings-arrival-to-sleep'));
  await tester.scrollUntilVisible(row, -400, scrollable: _recordsScrollable);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: row, matching: find.byIcon(Icons.add_circle_outline)),
  );
  await tester.pumpAndSettle();
}

void _expectNoForbiddenWords(WidgetTester tester) {
  const forbidden = ['권장', '치료', '처방', '진단', '효과'];
  final texts = tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(const ValueKey('guide-rules-screen')),
      matching: find.byType(Text),
    ),
  );
  final joined = texts.map((text) => text.data ?? '').join('\n');
  for (final word in forbidden) {
    expect(joined.contains(word), isFalse, reason: word);
  }
}
