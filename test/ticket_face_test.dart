import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/components/record_ticket_card.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/features/records/models/record.dart';

Future<void> _pump(WidgetTester tester, {Widget? photo, int photoCount = 0}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: TicketFace(
          title: 'Harmony',
          artistOrAuthor: 'Mrs. GREEN APPLE',
          date: DateTime(2024, 10, 31),
          photo: photo,
          photoCount: photoCount,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('チケットの公演名は入力どおりの大文字小文字で出せるフォントで表示する', (tester) async {
    await _pump(tester);

    final title = tester.widget<Text>(find.text('Harmony'));
    // Bebas Neue は小文字の字形がなく、すべて大文字に見えてしまう
    expect(title.style?.fontFamily, AppFonts.body);
    expect(title.style?.fontFamily, isNot(AppFonts.display));
    expect(find.text('2024.10.31  THU'), findsOneWidget);
  });

  testWidgets('写真がなければ半券に ADMIT ONE と入れる', (tester) async {
    await _pump(tester);

    expect(find.text('ADMIT ONE'), findsOneWidget);
  });

  testWidgets('写真があれば半券に敷き、2 枚以上なら枚数を添える', (tester) async {
    const photoKey = Key('photo');
    await _pump(
      tester,
      photo: const ColoredBox(key: photoKey, color: Colors.red),
      photoCount: 3,
    );

    expect(find.byKey(photoKey), findsOneWidget);
    expect(find.text('ADMIT ONE'), findsNothing);
    expect(find.bySemanticsLabel('写真3枚'), findsOneWidget);
  });

  testWidgets('一覧のチケットは文字のない余白を押しても開く', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: RecordTicketCard(
            record: Record(
              id: 'r1',
              type: RecordType.live,
              title: 'TOUR',
              artistOrAuthor: 'YOASOBI',
              date: DateTime(2026, 9, 12),
            ),
            onTap: () => taps++,
          ),
        ),
      ),
    );

    final face = tester.getRect(find.byType(TicketFace));
    // 公演名の右の、何も描いていないところ
    await tester.tapAt(Offset(face.left + face.width * 0.6, face.top + 14));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('写真が 1 枚なら枚数は出さない', (tester) async {
    await _pump(
      tester,
      photo: const ColoredBox(color: Colors.red),
      photoCount: 1,
    );

    expect(find.bySemanticsLabel(RegExp('写真')), findsNothing);
  });
}
