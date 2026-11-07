import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:osm_washabe/l10n/app_strings.dart';
import 'package:osm_washabe/main.dart';
import 'package:osm_washabe/services/app_preferences.dart';
import 'package:osm_washabe/views/startup/startup_screen.dart';
import 'package:osm_washabe/views/startup/usage_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await bootstrap(initializeNotifications: false);
    appSettings.language = 'ja';
  });

  test('文言は 3 言語にある（英語・ベトナム語が日本語のままにならない）', () {
    for (final key in ['次回から表示しない', 'はじめる', '使い方', 'ホーム画面へ', '使い方_コピー本文']) {
      final ja = AppStrings.text(key, 'ja');
      expect(ja, isNot(key == '使い方_コピー本文' ? key : ''));
      expect(AppStrings.text(key, 'en'), isNot(ja));
      expect(AppStrings.text(key, 'vi'), isNot(ja));
    }
  });

  testWidgets('スタートアップのボタンは下端に固定され、チェックが値として渡る', (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(home: StartupScreen(onContinue: (v) => result = v)),
    );
    await tester.pumpAndSettle();
    final button = tester.getBottomLeft(find.byType(FilledButton)).dy;
    expect(button, greaterThan(600 - 40));

    await tester.tap(find.text('次回から表示しない'));
    await tester.pump();
    await tester.tap(find.text('はじめる'));
    await tester.pump();
    expect(result, isTrue);
  });

  testWidgets('使い方画面に Chrome の説明と画像が出る', (tester) async {
    await tester.pumpWidget(MaterialApp(home: UsageScreen(onContinue: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('使い方'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('ホーム画面へ'), findsOneWidget);
  });

  test('スタートアップを OFF にすると使い方も OFF になる', () async {
    appSettings.showUsageScreen = true;
    appSettings.showStartupScreen = false;
    expect(appSettings.showUsageScreen, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppPreferences.showStartupScreenKey), isFalse);
    appSettings.showStartupScreen = true;
  });
}
