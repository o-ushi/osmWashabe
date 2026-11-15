import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:osm_washabe/main.dart';
import 'package:osm_washabe/views/main/app_root.dart';
import 'package:osm_washabe/views/startup/startup_screen.dart';
import 'package:osm_washabe/views/startup/usage_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await bootstrap(initializeNotifications: false);
    appSettings.language = 'ja';
  });

  setUp(() {
    appSettings.showStartupScreen = true;
    appSettings.showUsageScreen = false;
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppRoot(home: Scaffold(body: Text('home')))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('はじめる'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  }

  Future<void> swipeFrom(WidgetTester tester, double x) async {
    await tester.flingFrom(Offset(x, 300), const Offset(200, 0), 1000);
    await tester.pumpAndSettle();
  }

  testWidgets('メイン画面で左端から右へスワイプするとスタートアップに戻る', (tester) async {
    await pumpHome(tester);
    await swipeFrom(tester, 4);
    expect(find.byType(StartupScreen), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('使い方もオンなら使い方に戻る', (tester) async {
    appSettings.showUsageScreen = true;
    await tester.pumpWidget(
      const MaterialApp(home: AppRoot(home: Scaffold(body: Text('home')))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('はじめる'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ホーム画面へ'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    await swipeFrom(tester, 4);
    expect(find.byType(UsageScreen), findsOneWidget);
  });

  testWidgets('左端以外からのスワイプでは戻らない', (tester) async {
    await pumpHome(tester);
    await swipeFrom(tester, 150);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('スタートアップ画面がオフならスワイプしても戻らない', (tester) async {
    await pumpHome(tester);
    appSettings.showStartupScreen = false;
    await swipeFrom(tester, 4);
    expect(find.text('home'), findsOneWidget);
    expect(find.byType(StartupScreen), findsNothing);
  });
}
