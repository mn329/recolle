import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/widgets/content_switcher.dart';

void main() {
  Widget box(Object key, String text, {bool reduceMotion = false}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: ContentSwitcher(contentKey: key, child: Text(text)),
        ),
      );

  testWidgets('キーが変わると、前の中身を消しながら新しい中身を出す', (tester) async {
    await tester.pumpWidget(box('a', 'A'));
    await tester.pumpWidget(box('b', 'B'));
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('A'), findsNothing);
  });

  testWidgets('キーが同じなら、中身が変わってもすぐ入れ替える', (tester) async {
    await tester.pumpWidget(box('a', 'A'));
    await tester.pumpWidget(box('a', 'A2'));

    expect(find.text('A'), findsNothing);
    expect(find.text('A2'), findsOneWidget);
  });

  testWidgets('視差効果を減らす設定なら、すぐ入れ替える', (tester) async {
    await tester.pumpWidget(box('a', 'A', reduceMotion: true));
    await tester.pumpWidget(box('b', 'B', reduceMotion: true));
    await tester.pump();

    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsOneWidget);
  });

  Widget sliver(Object key, {bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: CustomScrollView(
        slivers: [
          SliverContentSwitcher(
            contentKey: key,
            sliver: SliverToBoxAdapter(child: Text('$key')),
          ),
        ],
      ),
    ),
  );

  double opacityOf(WidgetTester tester) => tester
      .widget<SliverFadeTransition>(find.byType(SliverFadeTransition))
      .opacity
      .value;

  testWidgets('一覧版は、キーが変わると新しい中身をふわっと出す', (tester) async {
    await tester.pumpWidget(sliver('a'));
    expect(opacityOf(tester), 1);

    await tester.pumpWidget(sliver('b'));
    await tester.pump(const Duration(milliseconds: 40));
    expect(opacityOf(tester), lessThan(1));

    await tester.pumpAndSettle();
    expect(opacityOf(tester), 1);
  });

  testWidgets('一覧版も、視差効果を減らす設定なら動かさない', (tester) async {
    await tester.pumpWidget(sliver('a', reduceMotion: true));
    await tester.pumpWidget(sliver('b', reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 40));

    expect(opacityOf(tester), 1);
  });
}
