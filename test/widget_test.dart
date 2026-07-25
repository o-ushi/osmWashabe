import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:osm_washabe/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('メイン画面が起動し分野ピッカーが使える', (WidgetTester tester) async {
    await bootstrap(initializeNotifications: false);
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
}
