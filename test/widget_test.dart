import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:osm_washabe/services/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:osm_washabe/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppPreferences.showStartupScreenKey: false,
    });
  });

  // bootstrap はプロセス内で 1 回だけ（appPreferences が late final）
  var booted = false;
  Future<void> ensureBooted() async {
    if (booted) return;
    await bootstrap(initializeNotifications: false);
    booted = true;
  }

  void setSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('メイン画面が起動し分野ピッカーが使える', (WidgetTester tester) async {
    // iPhone 縦（1 列）
    setSurface(tester, const Size(390, 844));
    await ensureBooted();
    await tester.pumpWidget(const OsmWashabeApp());
    await tester.pump();

    // デフォルト言語はベトナム語（iOS と同じ）
    expect(find.byTooltip('Từng câu'), findsOneWidget);
    expect(find.byTooltip('Thi thử'), findsOneWidget);
    expect(find.byTooltip('Rút chủ đề'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);

    appSettings.language = 'ja';
    await tester.pumpWidget(const OsmWashabeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('日常の身近な話題').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('ビジネスシーン').last);
    await tester.pumpAndSettle();

    expect(find.text('ビジネスシーン'), findsWidgets);
  });

  testWidgets('iPad 横向きは左右 2 画面になる', (WidgetTester tester) async {
    setSurface(tester, const Size(1180, 820));
    await ensureBooted();
    appSettings.language = 'ja';
    appSettings.scoringEnabled = false;
    await tester.pumpWidget(const OsmWashabeApp());
    await tester.pump();

    // 1問ずつ・採点オフ: 左にお題とタイマー、右に大きな残り秒数
    expect(find.byTooltip('お題を引く'), findsOneWidget);
    expect(find.text('45'), findsNWidgets(2));

    // 模擬試験の紹介は 1 列のまま（進行リストは出さない）
    await tester.tap(find.byTooltip('模擬試験'));
    await tester.pump();
    expect(find.text('いま'), findsNothing);
  });
}
