import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/core/widgets/app_root_builder.dart';

Future<TextStyle> _sheetTextStyle(
  WidgetTester tester, {
  TransitionBuilder? builder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      builder: builder,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: CupertinoButton(
              onPressed: () => showCupertinoSheet<void>(
                context: context,
                builder: (_) => const CupertinoPageScaffold(
                  child: Center(child: Text('シートの本文')),
                ),
              ),
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('開く'));
  await tester.pumpAndSettle();
  return DefaultTextStyle.of(tester.element(find.text('シートの本文'))).style;
}

void main() {
  testWidgets('シートの文字に、スタイル未設定を示す黄色の二重下線を付けない', (tester) async {
    final style = await _sheetTextStyle(tester, builder: buildAppRoot);

    expect(style.decorationStyle, isNot(TextDecorationStyle.double));
    expect(style.color, AppTheme.darkTheme.textTheme.bodyMedium!.color);
  });

  testWidgets('既定のスタイルがないと、シートの文字は黄色の二重下線になる', (tester) async {
    final style = await _sheetTextStyle(tester);

    expect(style.decorationStyle, TextDecorationStyle.double);
  });
}
