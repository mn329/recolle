import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/components/record_ticket_card.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/theme/app_theme.dart';

void main() {
  testWidgets('チケットの公演名は入力どおりの大文字小文字で出せるフォントで表示する', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: TicketFace(
            title: 'Harmony',
            artistOrAuthor: 'Mrs. GREEN APPLE',
            date: DateTime(2024, 10, 31),
            background: const SizedBox.shrink(),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Harmony'));
    // Bebas Neue は小文字の字形がなく、すべて大文字に見えてしまう
    expect(title.style?.fontFamily, AppFonts.body);
    expect(title.style?.fontFamily, isNot(AppFonts.display));
  });
}
