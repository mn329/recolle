import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';

/// ナビバーに渡した大見出しの中の文字。
Future<List<String?>> _largeTitleTexts(
  WidgetTester tester, {
  required String title,
  String? en,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: LargeTitleScrollView(
          title: title,
          enTitle: en,
          slivers: const [],
        ),
      ),
    ),
  );
  final bar = tester.widget<CupertinoSliverNavigationBar>(
    find.byType(CupertinoSliverNavigationBar),
  );
  final largeTitle = bar.largeTitle!;
  if (largeTitle is Text) return [largeTitle.data];
  final row = largeTitle as Row;
  return [
    for (final child in row.children)
      if (child is Text)
        child.data
      else if (child is Flexible && child.child is Text)
        (child.child as Text).data,
  ];
}

void main() {
  testWidgets('英字の見出しに、日本語の見出しを小さく添える', (tester) async {
    final texts = await _largeTitleTexts(
      tester,
      title: '振り返り',
      en: 'LOOK BACK',
    );

    expect(texts, ['LOOK BACK', '振り返り']);
    // 縮んだときは英字だけ
    expect(find.text('LOOK BACK'), findsOneWidget);
  });

  testWidgets('英字と同じ名前なら、日本語の見出しは添えない', (tester) async {
    final texts = await _largeTitleTexts(
      tester,
      title: 'RECOLLE',
      en: 'RECOLLE',
    );

    expect(texts, ['RECOLLE']);
  });

  testWidgets('英字の見出しがなければ、日本語の見出しをそのまま出す', (tester) async {
    final texts = await _largeTitleTexts(tester, title: '検索');

    expect(texts, ['検索']);
  });
}
