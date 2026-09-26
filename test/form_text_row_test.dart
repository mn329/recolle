import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/features/records/widgets/record_form/form_row_parts.dart';
import 'package:recolle/features/records/widgets/record_form/form_text_row.dart';

Future<void> _pump(WidgetTester tester, TextEditingController controller) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Column(
          children: [
            FormTextRow(
              controller: controller,
              placeholder: '会場',
              icon: CupertinoIcons.location,
              enLabel: 'VENUE',
            ),
            FormTextRow(controller: TextEditingController(), placeholder: '座席'),
          ],
        ),
      ),
    ),
  );
}

bool _isHighlighted(WidgetTester tester, String placeholder) {
  final highlight = tester.widget<FormRowHighlight>(
    find.ancestor(
      of: find.widgetWithText(CupertinoTextField, placeholder),
      matching: find.byType(FormRowHighlight),
    ),
  );
  return highlight.active;
}

void main() {
  testWidgets('英字の項目名は常に出し、和文は入力してプレースホルダーが消えてから添える', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    final jaLabel = find.descendant(
      of: find.byType(FormFieldLabel),
      matching: find.text('会場'),
    );
    expect(find.text('VENUE'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.location), findsOneWidget);
    expect(jaLabel, findsNothing);

    await tester.enterText(find.byType(CupertinoTextField).first, '日本武道館');
    await tester.pump();
    expect(jaLabel, findsOneWidget);

    await tester.enterText(find.byType(CupertinoTextField).first, '');
    await tester.pump();
    expect(jaLabel, findsNothing);
  });

  testWidgets('入力中の行だけを強調する', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(_isHighlighted(tester, '会場'), isFalse);
    expect(_isHighlighted(tester, '座席'), isFalse);

    await tester.showKeyboard(find.widgetWithText(CupertinoTextField, '会場'));
    await tester.pumpAndSettle();
    expect(_isHighlighted(tester, '会場'), isTrue);
    expect(_isHighlighted(tester, '座席'), isFalse);

    await tester.showKeyboard(find.widgetWithText(CupertinoTextField, '座席'));
    await tester.pumpAndSettle();
    expect(_isHighlighted(tester, '会場'), isFalse);
    expect(_isHighlighted(tester, '座席'), isTrue);
  });
}
