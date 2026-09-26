import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/screens/create_record_screen.dart';

class _NoFavorites extends FavoriteArtistsNotifier {
  @override
  Future<List<FavoriteArtist>> build() async => const [];
}

Future<void> _pumpScreen(WidgetTester tester, {Record? recordToEdit}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [favoriteArtistsProvider.overrideWith(_NoFavorites.new)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: CupertinoButton(
                onPressed: () => Navigator.push(
                  context,
                  CupertinoPageRoute<void>(
                    builder: (_) =>
                        CreateRecordScreen(recordToEdit: recordToEdit),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _field(String placeholder) =>
    find.widgetWithText(CupertinoTextField, placeholder);

NavBarTextButton _navButton(WidgetTester tester, String label) => tester
    .widget<NavBarTextButton>(find.widgetWithText(NavBarTextButton, label));

void main() {
  testWidgets('必須項目が揃うまで追加ボタンは無効で、足りない項目を案内する', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('新規記録'), findsOneWidget);
    expect(find.text('アーティストと公演名・ツアー名は必須です。'), findsOneWidget);
    expect(_navButton(tester, '追加').onPressed, isNull);

    await tester.enterText(_field('アーティスト'), 'YOASOBI');
    await tester.enterText(_field('公演名・ツアー名'), 'ZEPP TOUR');
    await tester.pump();

    expect(find.textContaining('必須です'), findsNothing);
    expect(_navButton(tester, '追加').onPressed, isNotNull);
  });

  testWidgets('種別に応じて入力欄の呼び方とライブ専用欄が切り替わる', (tester) async {
    await _pumpScreen(tester);
    expect(find.text('セットリスト'), findsOneWidget);
    expect(find.text('MCメモ'), findsOneWidget);

    await tester.tap(find.text('本'));
    await tester.pumpAndSettle();

    expect(_field('書名'), findsOneWidget);
    expect(_field('著者'), findsOneWidget);
    expect(find.text('セットリスト'), findsNothing);
    expect(find.text('MCメモ'), findsNothing);
  });

  testWidgets('入力途中で閉じると破棄の確認を出し、続けるを選ぶと画面に留まる', (tester) async {
    await _pumpScreen(tester);
    await tester.enterText(_field('あとで読み返したいことを自由に'), 'よかった');
    await tester.pump();

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(find.text('記録を破棄'), findsOneWidget);

    await tester.tap(find.text('編集を続ける'));
    await tester.pumpAndSettle();
    expect(find.text('新規記録'), findsOneWidget);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('記録を破棄'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('未変更なら確認なしで閉じられる', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('編集時は既存のセトリを曲数付きで表示する', (tester) async {
    await _pumpScreen(
      tester,
      recordToEdit: Record(
        id: 'r1',
        type: RecordType.live,
        title: 'TOUR',
        artistOrAuthor: 'YOASOBI',
        date: DateTime(2026, 9, 1),
        ticketImageUrl: '',
        setlist: 'アイドル\n祝福',
      ),
    );

    expect(find.text('記録を編集'), findsOneWidget);
    expect(find.text('2曲'), findsOneWidget);
    expect(find.text('アイドル'), findsOneWidget);
    expect(_navButton(tester, '保存').onPressed, isNotNull);
  });

  testWidgets('メールを貼り付けると公演名・アーティスト・取得元を入力する', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('メールから入力'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(CupertinoTextField).last,
      'ローソンチケットです。\n公演名：YOASOBI DOME LIVE\n出演者：YOASOBI\n公演日：2026/05/03',
    );
    await tester.pump();
    await tester.tap(find.text('読み取る'));
    await tester.pumpAndSettle();

    expect(find.text('メールから入力'), findsOneWidget);
    expect(find.text('YOASOBI DOME LIVE'), findsWidgets);
    expect(find.text('YOASOBI'), findsWidgets);
    expect(find.text('ローチケ'), findsOneWidget);
    expect(_navButton(tester, '追加').onPressed, isNotNull);
  });

  testWidgets('読み取れないメールならシートに留まって案内する', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('メールから入力'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).last, 'こんにちは');
    await tester.pump();
    await tester.tap(find.text('読み取る'));
    await tester.pump();

    expect(find.textContaining('読み取れませんでした'), findsOneWidget);
  });
}
