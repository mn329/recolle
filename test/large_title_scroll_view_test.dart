import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';

void main() {
  Widget buildView(String key, {required int itemCount}) => MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: LargeTitleScrollView(
        title: 'テスト',
        contentKey: key,
        slivers: [
          SliverList.list(
            children: [
              for (var i = 0; i < itemCount; i++)
                SizedBox(height: 100, child: Text('$key-$i')),
            ],
          ),
        ],
      ),
    ),
  );

  ScrollPosition positionOf(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  testWidgets('表示を切り替えると、初めての表示は先頭から、戻ると元の位置から見せる', (tester) async {
    await tester.pumpWidget(buildView('a', itemCount: 50));
    await tester.pumpAndSettle();
    positionOf(tester).jumpTo(1500);
    await tester.pump();

    await tester.pumpWidget(buildView('b', itemCount: 50));
    await tester.pumpAndSettle();
    // ナビバーは縮んだまま、内容の先頭に戻る
    expect(positionOf(tester).pixels, 52);
    expect(find.text('b-0'), findsOneWidget);

    await tester.pumpWidget(buildView('a', itemCount: 50));
    await tester.pumpAndSettle();
    expect(positionOf(tester).pixels, 1500);
  });

  testWidgets('覚えた位置が新しい内容より長ければ、末尾に収める', (tester) async {
    await tester.pumpWidget(buildView('a', itemCount: 50));
    await tester.pumpAndSettle();
    positionOf(tester).jumpTo(4000);
    await tester.pump();
    await tester.pumpWidget(buildView('b', itemCount: 50));
    await tester.pumpAndSettle();

    await tester.pumpWidget(buildView('a', itemCount: 12));
    await tester.pumpAndSettle();
    final position = positionOf(tester);
    expect(position.pixels, position.maxScrollExtent);
  });
}
