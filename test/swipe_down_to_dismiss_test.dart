import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:osm_washabe/widgets/swipe_down_to_dismiss.dart';

void main() {
  Future<void> pushDismissible(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: Text('Home')))),
    );
    final context = tester.element(find.text('Home'));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SwipeDownToDismiss(
          child: Container(color: Colors.white, width: 400, height: 800),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('素早い右方向のフリックでポップされる（右スワイプでの本来の動作）', (
    WidgetTester tester,
  ) async {
    await pushDismissible(tester);

    await tester.fling(find.byType(Container), const Offset(300, 0), 2000);
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('素早い下方向のフリックでポップされる（下スワイプでの本来の動作）', (
    WidgetTester tester,
  ) async {
    await pushDismissible(tester);

    await tester.fling(find.byType(Container), const Offset(0, 300), 2000);
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });

  // 右手親指で長く上スクロールする際、親指の付け根を軸にした弧を描く動きに
  // なりがちで、序盤のごくわずかな段階でたまたま右方向へ`_dragStartSlop`
  // (12px)分ドリフトすることがある。従来のコードは、そのドリフト量を
  // 「上方向の総移動量」と符号のまま比較していた（`totalDx >= totalDy`）ため、
  // 上方向の総移動量がどれだけ大きくても、負の値である限り常に負け、
  // 横スワイプ（削除）のロックが誤って掛かってしまっていた。
  testWidgets(
    '上スクロールの序盤にわずかな右ドリフトがあっても、'
    '全体としては上方向が支配的ならポップされない（回帰テスト）',
    (WidgetTester tester) async {
      await pushDismissible(tester);

      final gesture = await tester.startGesture(const Offset(200, 500));
      // 上方向へ大きく動く中、序盤にわずかな右ドリフト（12px超）が生じる。
      await gesture.moveTo(
        const Offset(203, 300),
        timeStamp: const Duration(milliseconds: 40),
      );
      await gesture.moveTo(
        const Offset(214, 250),
        timeStamp: const Duration(milliseconds: 80),
      );
      await gesture.moveTo(
        const Offset(216, 150),
        timeStamp: const Duration(milliseconds: 120),
      );
      // 終端で右方向へさらに動いても、ジェスチャー全体で見れば
      // 上方向の移動量が支配的であり続ける。
      await gesture.moveTo(
        const Offset(300, 148),
        timeStamp: const Duration(milliseconds: 130),
      );
      await gesture.up(timeStamp: const Duration(milliseconds: 130));
      await tester.pumpAndSettle();

      // ポップされていれば 'Home' が再表示される。修正後は上スクロールとして
      // 扱われ、このウィジェット自身はポップしない（`Navigator.pop`を
      // 呼ばないため、'Home' には戻らない）。
      expect(find.text('Home'), findsNothing);
    },
  );
}
