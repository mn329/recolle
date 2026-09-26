import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/components/liquid_glass_tab_bar.dart';

const _items = [
  LiquidGlassTabItem(
    icon: CupertinoIcons.tickets,
    activeIcon: CupertinoIcons.tickets_fill,
    label: 'ホーム',
  ),
  LiquidGlassTabItem(
    icon: CupertinoIcons.star,
    activeIcon: CupertinoIcons.star_fill,
    label: 'お気に入り',
  ),
  LiquidGlassTabItem(
    icon: CupertinoIcons.person_crop_circle,
    activeIcon: CupertinoIcons.person_crop_circle_fill,
    label: 'アカウント',
  ),
];

Future<List<int>> _pumpBar(WidgetTester tester, {int currentIndex = 0}) async {
  final tapped = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 360,
            child: LiquidGlassTabBar(
              items: _items,
              currentIndex: currentIndex,
              onTap: tapped.add,
            ),
          ),
        ),
      ),
    ),
  );
  return tapped;
}

void main() {
  testWidgets('タップしたタブに切り替わる', (tester) async {
    final tapped = await _pumpBar(tester);

    await tester.tap(find.text('お気に入り'));
    await tester.pumpAndSettle();

    expect(tapped, [1]);
  });

  testWidgets('横スワイプで指を離した位置のタブに切り替わる', (tester) async {
    final tapped = await _pumpBar(tester);

    await tester.drag(find.text('ホーム'), const Offset(260, 0));
    await tester.pumpAndSettle();

    expect(tapped, [2]);
  });

  testWidgets('長押ししてから動かすと、離した位置のタブに切り替わる', (tester) async {
    final tapped = await _pumpBar(tester, currentIndex: 2);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('アカウント')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tapped, [1]);
  });

  testWidgets('元のタブの上で離したら切り替えない', (tester) async {
    final tapped = await _pumpBar(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('ホーム')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(10, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tapped, isEmpty);
  });
}
