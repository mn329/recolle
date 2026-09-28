import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
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

Future<List<int>> _pumpBar(
  WidgetTester tester, {
  int currentIndex = 0,
  bool highContrast = false,
  bool disableAnimations = false,
}) async {
  final tapped = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          highContrast: highContrast,
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
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

  testWidgets('「コントラストを上げる」が ON なら透過をやめ、タップも効く', (tester) async {
    final tapped = await _pumpBar(tester, highContrast: true);

    expect(find.byType(LiquidGlass), findsNothing);
    await tester.tap(find.text('アカウント'));
    expect(tapped, [2]);
  });

  testWidgets('「視差効果を減らす」が ON ならガラスの伸び縮みを止める', (tester) async {
    await _pumpBar(tester, disableAnimations: true);

    expect(find.byType(LiquidGlass), findsOneWidget);
    expect(find.byType(LiquidStretch), findsNothing);
  });

  group('supportsShaderGlass', () {
    bool check({bool shader = true, bool ios = true, String version = ''}) =>
        LiquidGlassTabBar.supportsShaderGlass(
          shaderSupported: shader,
          isIOS: ios,
          osVersion: version,
        );

    test('iOS 26 以降だけリキッドグラスにする', () {
      expect(check(version: 'Version 26.0 (Build 23A344)'), isTrue);
      expect(check(version: 'Version 27.1 (Build 24B1)'), isTrue);
      expect(check(version: 'Version 18.6 (Build 22G86)'), isFalse);
    });

    test('シェーダー非対応なら常にすりガラス', () {
      expect(check(shader: false, version: 'Version 26.0'), isFalse);
      expect(check(shader: false, ios: false), isFalse);
    });

    test('iOS 以外はシェーダー対応ならリキッドグラス', () {
      expect(check(ios: false, version: 'Android 16'), isTrue);
    });

    test('バージョンを読めなければ安全側ですりガラス', () {
      expect(check(version: 'unknown'), isFalse);
    });
  });
}
