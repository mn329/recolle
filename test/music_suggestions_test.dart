import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:recolle/features/records/widgets/music_suggestions.dart';

class _FakeItunesClient extends ItunesClient {
  @override
  Future<List<ItunesArtist>> searchArtists(
    String term, {
    int limit = 8,
  }) async => [
    for (var i = 0; i < 5; i++)
      ItunesArtist(id: i, name: 'ONE OK ROCK $i', genre: 'Rock'),
  ];
}

void main() {
  /// 入力欄の下に候補が出る、縦に長いフォームを模した画面。
  Future<ScrollPosition> pumpForm(
    WidgetTester tester, {
    required double keyboardHeight,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    // 画面 800x600 のうち下から keyboardHeight をキーボードが覆う
    tester.view
      ..physicalSize = const Size(800, 600)
      ..devicePixelRatio = 1
      ..viewInsets = FakeViewPadding(bottom: keyboardHeight);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itunesClientProvider.overrideWithValue(_FakeItunesClient()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [
                  const SizedBox(height: 250),
                  ArtistSuggestions(query: 'one ok', onPick: (_) {}),
                  const SizedBox(height: 600),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // 入力の間引き・検索・枠が広がるアニメーション・スクロールを待つ
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    return controller.position;
  }

  testWidgets('入力中は、あとから広がった候補がキーボードに隠れないようスクロールする', (tester) async {
    final position = await pumpForm(tester, keyboardHeight: 300);

    expect(find.text('ONE OK ROCK 4'), findsOneWidget);
    expect(position.pixels, greaterThan(0));
    // キーボードの上（画面の高さ 600 − キーボード 300）に候補の最後の行が収まる
    final lastRow = tester.getRect(find.text('ONE OK ROCK 4'));
    expect(lastRow.bottom, lessThanOrEqualTo(300));
  });

  testWidgets('キーボードが出ていなければ、勝手にスクロールしない', (tester) async {
    final position = await pumpForm(tester, keyboardHeight: 0);

    expect(find.text('ONE OK ROCK 4', skipOffstage: false), findsOneWidget);
    expect(position.pixels, 0);
  });
}
