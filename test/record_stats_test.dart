import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/record_stats.dart';
import 'package:recolle/features/records/screens/insights_screen.dart';

Record _live(
  String id,
  DateTime date, {
  String artist = 'YOASOBI',
  String? venue,
  int? price,
  String? setlist,
  RecordType type = RecordType.live,
}) => Record(
  id: id,
  type: type,
  title: 'T$id',
  artistOrAuthor: artist,
  date: date,
  ticketImageUrl: '',
  venue: venue,
  ticketPrice: price,
  setlist: setlist,
);

void main() {
  final now = DateTime(2026, 9, 27);
  final records = [
    _live(
      '1',
      DateTime(2026, 3, 1),
      venue: '東京ドーム',
      price: 10000,
      setlist: '夜に駆ける\nアイドル\n夜に駆ける',
    ),
    _live(
      '2',
      DateTime(2026, 3, 20),
      artist: 'yoasobi ',
      venue: '東京ドーム',
      setlist: 'アイドル',
    ),
    _live('3', DateTime(2026, 8, 5), artist: 'Vaundy', price: 8000),
    _live('4', DateTime(2025, 12, 31), artist: 'Vaundy', price: 9000),
    _live('future', DateTime(2026, 12, 24), price: 99999),
    _live('movie', DateTime(2026, 5, 5), type: RecordType.movie),
  ];

  test('年を指定すると、その年の過去の記録だけを集計する', () {
    final stats = computeStats(records, now: now, year: 2026);

    expect(stats.liveCount, 3);
    expect(stats.countsByType[RecordType.movie], 1);
    expect(stats.totalTicketPrice, 18000);
    expect(stats.averageTicketPrice, 9000);
    expect(stats.liveCountsByMonth[2], 2);
    expect(stats.liveCountsByMonth[7], 1);
  });

  test('表記ゆれをまとめてランキングし、同じ公演で重複した曲は 1 回と数える', () {
    final stats = computeStats(records, now: now, year: 2026);

    expect(stats.topArtists.first, (label: 'YOASOBI', count: 2));
    expect(stats.topVenues, [(label: '東京ドーム', count: 2)]);
    expect(stats.topSongs.first, (label: 'アイドル', count: 2));
    expect(stats.topSongs[1], (label: '夜に駆ける', count: 1));
  });

  test('年を指定しなければ全期間、未来の公演は含めない', () {
    final stats = computeStats(records, now: now);

    expect(stats.liveCount, 4);
    expect(stats.topArtists.map((a) => a.label), ['Vaundy', 'YOASOBI']);
    expect(stats.totalTicketPrice, 27000);
  });

  test('アーティストで絞り込み、コラボ表記の記録も含める', () {
    final withCollab = [
      ...records,
      _live('collab', DateTime(2026, 6, 1), artist: 'Vaundy × YOASOBI'),
    ];

    expect(filterByArtist(withCollab, 'Vaundy').map((r) => r.id), [
      '3',
      '4',
      'collab',
    ]);
    expect(filterByArtist(withCollab, null), hasLength(withCollab.length));
  });

  test('初めて・最後に行った日と、行ったライブを新しい順に返す', () {
    final stats = computeStats(filterByArtist(records, 'Vaundy'), now: now);

    expect(stats.firstLiveDate, DateTime(2025, 12, 31));
    expect(stats.lastLiveDate, DateTime(2026, 8, 5));
    expect(stats.lives.map((r) => r.id), ['3', '4']);
  });

  test('記録がある年を新しい順に返す', () {
    expect(yearsWithRecords(records, now), [2026, 2025]);
  });

  test('チケット代が 1 件もなければ平均は null', () {
    final stats = computeStats([_live('1', DateTime(2026, 1, 1))], now: now);
    expect(stats.averageTicketPrice, isNull);
  });

  testWidgets('振り返り画面に回数とランキングを表示する', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordsProvider.overrideWith((ref) => Stream.value(records)),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const InsightsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('集計'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('すべての年'));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsWidgets);
    expect(find.text('よく行ったアーティスト'), findsOneWidget);

    // ランキングの行を押すと、そのアーティストの振り返りに切り替わる
    await tester.tap(find.widgetWithText(GroupedRow, 'Vaundy'));
    await tester.pumpAndSettle();
    expect(find.text('よく行ったアーティスト'), findsNothing);
    expect(find.text('初めて行った日'), findsOneWidget);
    final page = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('行ったライブ・2回'),
      200,
      scrollable: page,
    );
    expect(find.text('T3'), findsOneWidget);
    expect(find.text('T4'), findsOneWidget);

    // お気に入りにないアーティストでも、選んだ間はチップが出て「すべて」で戻せる
    expect(find.widgetWithText(CapsuleChip, 'Vaundy'), findsOneWidget);
    await tester.tap(find.widgetWithText(CapsuleChip, 'すべて'));
    await tester.pumpAndSettle();
    expect(find.text('よく行ったアーティスト'), findsOneWidget);
  });
}
