// App Store 用のスクリーンショットを撮るための画面巡回。
//
// scripts/capture_screenshots.sh から実行する。画面が整うたびに `SHOT:<名前>` を出力し、
// スクリプト側がその合図で simctl のスクリーンショットを撮る（ステータスバー込みの実寸になる）。
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:recolle/main.dart' as app;

/// アニメーションが続く画面でも進められるよう、[pumpAndSettle] ではなく時間で進める。
Future<void> _wait(WidgetTester tester, [int seconds = 2]) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [finder] が一覧に描画されるまで、画面をスクロールする（遅延描画の一覧のため）。
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -500),
    );
    await _wait(tester, 1);
  }
}

/// 撮影の合図。スクリプトが撮り終わるまで、画面をそのままにしておく。
Future<void> _shot(WidgetTester tester, String name) async {
  await _wait(tester, 1);
  // ignore: avoid_print
  print('SHOT:$name');
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App Store スクリーンショット', (tester) async {
    app.main();
    await _wait(tester, 8);

    // 1. ホーム
    await _shot(tester, '01_home');

    // 映画タブ（ライブ以外の記録も残せることを見せる）
    await tester.tap(find.text('映画').first);
    await _wait(tester, 2);
    await _shot(tester, '08_movies');
    await tester.tap(find.text('ライブ').first);
    await _wait(tester, 2);

    // 2. 記録の詳細（チケット）
    final past = find.text('King Gnu Dome Tour 2026');
    await _scrollTo(tester, past);
    await tester.tap(past.first);
    await _wait(tester, 2);
    await _shot(tester, '02_detail');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -480));
    await _wait(tester, 1);
    await _shot(tester, '03_detail_setlist');
    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await _wait(tester, 1);

    // 3. 振り返り（集計）とカレンダー
    await tester.tap(find.text('振り返り').last);
    await _wait(tester, 2);
    await _shot(tester, '04_insights');
    await tester.tap(find.text('カレンダー').first);
    await _wait(tester, 2);
    // 記録の多い前の月に切り替える
    await tester.tap(find.byIcon(CupertinoIcons.chevron_left).first);
    await _wait(tester, 2);
    await _shot(tester, '05_calendar');

    // 4. お気に入り
    await tester.tap(find.text('お気に入り').last);
    await _wait(tester, 2);
    await _shot(tester, '06_favorites');

    // 5. ホームから検索
    await tester.tap(find.text('ホーム').last);
    await _wait(tester, 1);
    await tester.tap(find.bySemanticsLabel('検索'));
    await _wait(tester, 1);
    await tester.enterText(find.byType(EditableText).first, 'YOASOBI');
    await _wait(tester, 2);
    await _shot(tester, '07_search');
    // ignore: avoid_print
    print('SHOT:DONE');
  });
}
