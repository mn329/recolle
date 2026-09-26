import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/share/record_share_card.dart';

final _record = Record(
  id: 'r1',
  type: RecordType.live,
  title: 'Mrs. GREEN APPLE ARENA TOUR 2026 "BABEL no TOH" SUPER LONG TITLE',
  artistOrAuthor: 'Mrs. GREEN APPLE',
  date: DateTime(2026, 9, 1),
  ticketImageUrl: '',
  venue: 'さいたまスーパーアリーナ',
  seat: 'アリーナ A5ブロック 12列 34番',
  ticketPrice: 12800,
  startTime: const ClockTime(18, 0),
  setlist: [for (var i = 1; i <= 15; i++) '曲 $i'].join('\n'),
);

void main() {
  for (final style in ShareCardStyle.values) {
    testWidgets('${style.label}：崩れずに描画し、載らない曲数を添える', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordShareCard(record: _record, style: style),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('ほか 3 曲'), findsOneWidget);
      expect(
        tester.getSize(find.byType(RecordShareCard)).width,
        RecordShareCard.width,
      );
    });
  }

  testWidgets('任意項目が空でも描画できる', (tester) async {
    final minimal = Record(
      id: 'r2',
      type: RecordType.movie,
      title: '映画',
      artistOrAuthor: '監督',
      date: DateTime(2026, 1, 1),
      ticketImageUrl: '',
    );
    for (final style in ShareCardStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordShareCard(record: minimal, style: style),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
