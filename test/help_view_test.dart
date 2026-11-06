import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:osm_washabe/l10n/app_strings.dart';
import 'package:osm_washabe/notifiers/app_settings.dart';
import 'package:osm_washabe/services/app_preferences.dart';
import 'package:osm_washabe/views/help/help_view.dart';
import 'package:osm_washabe/views/privacy/privacy_view.dart';

const _sections = {
  'one': 3,
  'prep': 3,
  'mock': 2,
  'read': 1,
  'import': 2,
  'score': 3,
  'last': 1,
  'voice': 2,
  'crash': 1,
};

void main() {
  late AppSettingsNotifier settings;

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'osmWAshabe',
      packageName: 'com.osamushikubo.osmWashabe',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettingsNotifier()..bind(await AppPreferences.load());
    settings.language = 'ja';
  });

  Future<void> pumpHelp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 9000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: HelpView(settings: settings)));
    await tester.pumpAndSettle();
  }

  for (final lang in ['ja', 'en', 'vi']) {
    test('$lang: 各節の文言があり、手順は 3 つまでで短い', () {
      final japanese = RegExp(r'[\u3040-\u30ff\u4e00-\u9fff]');
      for (final MapEntry(key: id, value: count) in _sections.entries) {
        expect(count, lessThanOrEqualTo(3));
        for (final key in [
          'help.$id.title',
          for (var i = 1; i <= count; i++) 'help.$id.$i',
        ]) {
          final text = key.tr(lang);
          expect(text, isNot(key), reason: key);
          expect(text.length, lessThanOrEqualTo(80), reason: key);
          if (lang != 'ja') {
            expect(japanese.hasMatch(text), isFalse, reason: key);
          }
        }
      }
    });
  }

  testWidgets('操作マニュアルは無く、節は閉じて始まり、開くと番号順の手順が出る', (tester) async {
    await pumpHelp(tester);
    expect(find.byIcon(Icons.menu_book_outlined), findsNothing);
    expect(find.text('help.one.1'.tr('ja')), findsNothing);

    final card = find.byKey(const ValueKey('help-section-one'));
    await tester.tap(find.text('help.one.title'.tr('ja')));
    await tester.pumpAndSettle();
    for (var i = 1; i <= 3; i++) {
      expect(
        find.descendant(of: card, matching: find.text('$i')),
        findsOneWidget,
      );
      expect(find.text('help.one.$i'.tr('ja')), findsOneWidget);
    }

    await tester.tap(find.text('help.one.title'.tr('ja')));
    await tester.pumpAndSettle();
    expect(find.text('help.one.1'.tr('ja')), findsNothing);
  });

  testWidgets('プライバシーはヘルプから開く', (tester) async {
    await pumpHelp(tester);
    await tester.tap(find.byKey(const ValueKey('help-privacy')));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyView), findsOneWidget);
  });
}
