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
  venue: 'さいたまスーパーアリーナ',
  seat: 'アリーナ A5ブロック 12列 34番',
  ticketPrice: 12800,
  startTime: const ClockTime(18, 0),
  setlist: [for (var i = 1; i <= 45; i++) '曲 $i'].join('\n'),
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
      expect(find.text('ほか 5 曲'), findsOneWidget);
      expect(
        tester.getSize(find.byType(RecordShareCard)).width,
        RecordShareCard.width,
      );
    });
  }

  test('対バン・フェスは出演者に続けて、お目当てのセトリも載せる', () {
    final fes = Record(
      id: 'r3',
      type: RecordType.live,
      title: 'FES',
      artistOrAuthor: 'A',
      date: DateTime(2026, 8, 1),
      eventFormat: EventFormat.festival,
      acts: const [
        RecordAct(artist: 'A', songs: ['a1', 'a2'], isMain: true),
        RecordAct(artist: 'B', songs: ['b1']),
      ],
    );

    final lists = RecordShareCard.listsFor(fes);

    expect(lists.map((l) => l.heading), ['LINEUP', 'SETLIST · A']);
    expect(lists[0].items, ['★ A', 'B']);
    expect(lists[1].items, ['a1', 'a2']);
  });

  testWidgets('どの色でも崩れずに描画できる', (tester) async {
    for (final theme in ShareCardTheme.values) {
      for (final style in ShareCardStyle.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RecordShareCard(
                  record: _record,
                  style: style,
                  theme: theme,
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('任意項目が空でも描画できる', (tester) async {
    final minimal = Record(
      id: 'r2',
      type: RecordType.movie,
      title: '映画',
      artistOrAuthor: '監督',
      date: DateTime(2026, 1, 1),
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
