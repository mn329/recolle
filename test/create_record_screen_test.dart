import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
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

FilledButton _saveButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

void main() {
  testWidgets('必須項目が揃うまで保存ボタンは無効で、足りない項目を案内する', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('公演名・ツアー名とアーティストを入力してください'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'アーティスト'),
      'YOASOBI',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '公演名・ツアー名'),
      'ZEPP TOUR',
    );
    await tester.pump();

    expect(find.text('記録を保存'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('種別に応じて入力欄の呼び方とライブ専用欄が切り替わる', (tester) async {
    await _pumpScreen(tester);
    expect(find.text('SETLIST'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'MCメモ'), findsOneWidget);

    await tester.tap(find.text('本'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '書名'), findsOneWidget);
    expect(find.widgetWithText(TextField, '著者'), findsOneWidget);
    expect(find.text('SETLIST'), findsNothing);
    expect(find.widgetWithText(TextField, 'MCメモ'), findsNothing);
  });

  testWidgets('入力途中で閉じると破棄の確認を出し、続けるを選ぶと画面に留まる', (tester) async {
    await _pumpScreen(tester);
    await tester.enterText(find.widgetWithText(TextField, '感想'), 'よかった');
    await tester.pump();

    await tester.tap(find.byTooltip('閉じる'));
    await tester.pumpAndSettle();
    expect(find.text('入力内容を破棄しますか？'), findsOneWidget);

    await tester.tap(find.text('編集を続ける'));
    await tester.pumpAndSettle();
    expect(find.text('NEW RECORD'), findsOneWidget);

    await tester.tap(find.byTooltip('閉じる'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('破棄する'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('未変更なら確認なしで閉じられる', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.byTooltip('閉じる'));
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

    expect(find.text('EDIT RECORD'), findsOneWidget);
    expect(find.text('2曲'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'アイドル'), findsOneWidget);
    expect(find.text('変更を保存'), findsOneWidget);
  });
}
