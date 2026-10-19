import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/music/screens/song_detail_screen.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/record_stats.dart';
import 'package:recolle/features/records/screens/insights_screen.dart';
import 'package:recolle/features/records/screens/live_list_screen.dart';
import 'package:recolle/features/records/screens/venue_detail_screen.dart';

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
  venue: venue,
  ticketPrice: price,
  setlist: setlist,
);

/// ジャンルの切り替えのセグメント。「本」などは集計の単位と同じ文字なので、切り替えの中から探す。
Finder genreSegment(String label) => find.descendant(
  of: find.byType(IosSegmentedControl<InsightsGenre>),
  matching: find.text(label),
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
    _live('future', DateTime(2026, 12, 24), price: 5000),
    _live('movie', DateTime(2026, 5, 5), type: RecordType.movie),
  ];

  test('年を指定すると、その年の記録を集計する。これからの予定も数える', () {
    final stats = computeStats(records, now: now, year: 2026);

    expect(stats.liveCount, 4);
    expect(stats.countsByType[RecordType.movie], 1);
    expect(stats.totalTicketPrice, 23000);
    expect(stats.averageTicketPrice, 7667);
    expect(stats.liveCountsByMonth[2], 2);
    expect(stats.liveCountsByMonth[7], 1);
    expect(stats.liveCountsByMonth[11], 1);
  });

  test('表記ゆれをまとめてランキングし、同じ公演で重複した曲は 1 回と数える', () {
    final stats = computeStats(records, now: now, year: 2026);

    expect(stats.topArtists.first, (label: 'YOASOBI', count: 3));
    expect(stats.topVenues, [(label: '東京ドーム', count: 2)]);
    expect(stats.topSongs.first, (title: 'アイドル', artist: 'YOASOBI', count: 2));
    expect(stats.topSongs[1], (title: '夜に駆ける', artist: 'YOASOBI', count: 1));
  });

  test('年を指定しなければ全期間を集計する', () {
    final stats = computeStats(records, now: now);

    expect(stats.liveCount, 5);
    expect(stats.topArtists.map((a) => a.label), ['YOASOBI', 'Vaundy']);
    expect(stats.totalTicketPrice, 32000);
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

  test('初めて・最後に行った日には、これからの予定を含めない', () {
    final stats = computeStats(filterByArtist(records, 'YOASOBI'), now: now);

    expect(stats.firstLiveDate, DateTime(2026, 3, 1));
    expect(stats.lastLiveDate, DateTime(2026, 3, 20));
    // 一覧には予定も並ぶ（新しい順）
    expect(stats.lives.map((r) => r.id), ['future', '2', '1']);
  });

  test('初めて・最後に行った日と、ライブを新しい順に返す', () {
    final stats = computeStats(filterByArtist(records, 'Vaundy'), now: now);

    expect(stats.firstLiveDate, DateTime(2025, 12, 31));
    expect(stats.lastLiveDate, DateTime(2026, 8, 5));
    expect(stats.lives.map((r) => r.id), ['3', '4']);
  });

  group('対バン・フェス', () {
    final fes = Record(
      id: 'fes',
      type: RecordType.live,
      title: 'ROCK IN JAPAN',
      artistOrAuthor: 'Vaundy',
      date: DateTime(2026, 8, 8),
      endDate: DateTime(2026, 8, 9),
      eventFormat: EventFormat.festival,
      acts: const [
        RecordAct(artist: 'Vaundy', songs: ['怪獣の花唄'], isMain: true, day: 1),
        RecordAct(artist: 'sumika', songs: ['Lovers'], day: 1),
        RecordAct(artist: 'back number', songs: ['水平線'], day: 2),
      ],
    );
    final withFes = [...records, fes];

    test('形式ごとの回数と、出演者全員を含めた観たアーティスト数を数える', () {
      final stats = computeStats(withFes, now: now, year: 2026);

      expect(stats.liveCount, 5);
      expect(stats.liveCountsByFormat[EventFormat.oneman], 4);
      expect(stats.liveCountsByFormat[EventFormat.festival], 1);
      // YOASOBI・Vaundy・sumika・back number
      expect(stats.artistCount, 4);
      expect(stats.topArtists.first, (label: 'YOASOBI', count: 3));
      expect(
        stats.topSongs,
        contains((title: '水平線', artist: 'back number', count: 1)),
      );
    });

    test('同じ回数なら大文字小文字を区別せずに並べる', () {
      final stats = computeStats(withFes, now: now, year: 2026);

      expect(stats.topArtists.map((a) => a.label), [
        'YOASOBI',
        'Vaundy',
        'back number',
        'sumika',
      ]);
    });

    test('アーティストで絞ると、その出演者の曲だけを数える', () {
      final stats = computeStats(
        filterByArtist(withFes, 'Vaundy'),
        now: now,
        artist: 'Vaundy',
      );

      expect(stats.topSongs, [(title: '怪獣の花唄', artist: 'Vaundy', count: 1)]);
    });
  });

  test('同じ曲名でもアーティストが違えば別の曲として数える', () {
    final stats = computeStats([
      _live('1', DateTime(2026, 1, 1), artist: 'A', setlist: 'Lovers'),
      _live('2', DateTime(2026, 2, 1), artist: 'B', setlist: 'Lovers'),
      _live('3', DateTime(2026, 3, 1), artist: 'a', setlist: 'lovers'),
    ], now: now);

    expect(stats.topSongs, [
      (title: 'Lovers', artist: 'A', count: 2),
      (title: 'Lovers', artist: 'B', count: 1),
    ]);
  });

  test('会場で絞り込むと、その会場で聴いた曲と行ったライブを集計する', () {
    final atVenue = filterByVenue([
      _live('1', DateTime(2026, 1, 1), venue: '日本武道館', setlist: '夜に駆ける'),
      _live('2', DateTime(2026, 2, 1), venue: '日本 武道館', setlist: '夜に駆ける\n群青'),
      _live('3', DateTime(2026, 3, 1), venue: 'さいたまスーパーアリーナ', setlist: '群青'),
      _live('4', DateTime(2026, 4, 1)),
    ], '日本武道館');
    final stats = computeStats(atVenue, now: now);

    expect(stats.lives.map((r) => r.id), ['2', '1']);
    expect(stats.topSongs.first, (title: '夜に駆ける', artist: 'YOASOBI', count: 2));
    expect(stats.topSongs.map((s) => s.title), ['夜に駆ける', '群青']);
  });

  test('記録がある年を新しい順に返す', () {
    expect(yearsWithRecords(records), [2026, 2025]);
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

    await tester.tap(find.text('すべての年'));
    await tester.pumpAndSettle();
    await tester.tap(genreSegment('ライブ'));
    await tester.pumpAndSettle();
    expect(find.text('5'), findsWidgets);
    expect(find.text('よく行ったアーティスト'), findsOneWidget);

    // よく聴いた曲の行から曲の詳細へ移れる
    final songRow = find.widgetWithText(GroupedRow, 'アイドル');
    await tester.scrollUntilVisible(
      songRow,
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(songRow);
    await tester.pumpAndSettle();
    expect(find.byType(SongDetailScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(SongDetailScreen))).pop();
    await tester.pumpAndSettle();

    // ランキングの行を押すと、そのアーティストの振り返りに切り替わる
    await tester.tap(find.widgetWithText(GroupedRow, 'Vaundy'));
    // パッと入れ替えず、しばらくは前の中身が消えていく途中で重なって見える
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('よく行ったアーティスト'), findsOneWidget);
    expect(find.text('初めて行った日'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('よく行ったアーティスト'), findsNothing);
    expect(find.text('初めて行った日'), findsOneWidget);
    final page = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(find.text('ライブ・2回'), 200, scrollable: page);
    expect(find.text('T3'), findsOneWidget);
    expect(find.text('T4'), findsOneWidget);

    // お気に入りにないアーティストでも、選んだ間はチップが出て「すべて」で戻せる
    expect(find.widgetWithText(CapsuleChip, 'Vaundy'), findsOneWidget);
    await tester.tap(find.widgetWithText(CapsuleChip, 'すべて'));
    await tester.pumpAndSettle();
    expect(find.text('よく行ったアーティスト'), findsOneWidget);
  });

  testWidgets('ライブの回数や月別の棒から、そのライブの一覧を開ける', (tester) async {
    final semantics = tester.ensureSemantics();
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
    await tester.tap(find.text('すべての年'));
    await tester.pumpAndSettle();
    await tester.tap(genreSegment('ライブ'));
    await tester.pumpAndSettle();

    // ジャンルの切り替えにも同じ「ライブ」があるので、後ろ（集計のタイル）を押す
    await tester.tap(find.text('ライブ').last);
    await tester.pumpAndSettle();
    expect(find.byType(LiveListScreen), findsOneWidget);
    expect(find.text('すべてのライブ・5回'), findsOneWidget);
    Navigator.of(tester.element(find.byType(LiveListScreen))).pop();
    await tester.pumpAndSettle();

    final march = find.bySemanticsLabel('3月 2回');
    await tester.ensureVisible(march);
    await tester.pumpAndSettle();
    await tester.tap(march);
    await tester.pumpAndSettle();
    expect(find.text('3月（全期間）のライブ・2回'), findsOneWidget);
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('T2'), findsOneWidget);
    expect(find.text('T3'), findsNothing);
    semantics.dispose();
  });

  testWidgets('よく行った会場の行から、その会場で聴いた曲を開ける', (tester) async {
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
    await tester.tap(find.text('すべての年'));
    await tester.pumpAndSettle();
    await tester.tap(genreSegment('ライブ'));
    await tester.pumpAndSettle();

    final venueRow = find.widgetWithText(GroupedRow, '東京ドーム');
    await tester.scrollUntilVisible(
      venueRow,
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(venueRow);
    await tester.pumpAndSettle();

    expect(find.byType(VenueDetailScreen), findsOneWidget);
    expect(find.text('この会場のライブ・2回'), findsOneWidget);
    expect(find.text('この会場で聴いた曲'), findsOneWidget);
    expect(find.widgetWithText(GroupedRow, 'アイドル'), findsOneWidget);
    expect(find.widgetWithText(GroupedRow, '夜に駆ける'), findsOneWidget);
  });

  group('ジャンル別', () {
    final genreRecords = [
      _live('1', DateTime(2026, 3, 1), venue: '東京ドーム'),
      _live('4', DateTime(2025, 12, 31), artist: 'Vaundy'),
      _live(
        'm1',
        DateTime(2026, 5, 5),
        type: RecordType.movie,
        venue: 'TOHOシネマズ',
        price: 1900,
      ),
      _live(
        'm2',
        DateTime(2026, 6, 6),
        type: RecordType.movie,
        venue: 'tohoシネマズ ',
        price: 2100,
      ),
      _live('m3', DateTime(2025, 1, 10), type: RecordType.movie),
      _live('m-future', DateTime(2026, 12, 1), type: RecordType.movie),
      _live(
        'b1',
        DateTime(2026, 2, 3),
        type: RecordType.book,
        venue: '本屋',
        price: 1500,
      ),
    ];

    test('ジャンルで絞り込む。null なら絞らない', () {
      expect(filterByType(genreRecords, RecordType.book).map((r) => r.id), [
        'b1',
      ]);
      expect(filterByType(genreRecords, null), genreRecords);
    });

    test('映画の件数・金額・月別・会場を、これからの予定も含めて集計する', () {
      final stats = computeGenreStats(genreRecords, type: RecordType.movie);

      expect(stats.count, 4);
      expect(stats.records.map((r) => r.id), ['m-future', 'm2', 'm1', 'm3']);
      expect(stats.totalPrice, 4000);
      expect(stats.averagePrice, 2000);
      expect(stats.countsByMonth[4], 1);
      expect(stats.countsByMonth[5], 1);
      expect(stats.countsByMonth[0], 1);
      expect(stats.countsByMonth[11], 1);
      // 表記ゆれはまとめて数える
      expect(stats.topVenues, [(label: 'TOHOシネマズ', count: 2)]);
    });

    test('年を指定すると、その年の記録だけを集計する', () {
      final stats = computeGenreStats(
        genreRecords,
        type: RecordType.movie,
        year: 2025,
      );

      expect(stats.count, 1);
      expect(stats.averagePrice, isNull);
      expect(stats.topVenues, isEmpty);
    });

    test('場所の入力欄がない本は、会場を集計しない', () {
      final stats = computeGenreStats(genreRecords, type: RecordType.book);

      expect(stats.count, 1);
      expect(stats.totalPrice, 1500);
      expect(stats.topVenues, isEmpty);
    });

    test('登録した記録は、これからの予定も保存した日のうちから数える', () {
      final today = DateTime(2026, 9, 27, 12);
      final records = [
        _live('book', today, type: RecordType.book, price: 1200),
        // 先に取ったチケット代も、家計簿として数える
        _live('live', DateTime(2026, 11, 3), price: 8800),
        _live(
          'movie',
          DateTime(2027, 1, 5),
          type: RecordType.movie,
          price: 1900,
        ),
      ];

      final stats = computeOverviewStats(records);

      expect(stats.count, 3);
      expect(stats.totalPrice, 11900);
      expect(yearsWithRecords(records), [2027, 2026]);
    });

    test('全ジャンルをまとめて集計する', () {
      final stats = computeOverviewStats(genreRecords);

      expect(stats.count, 7);
      expect(stats.byType.map((g) => g.count), [2, 4, 1, 0]);
      expect(stats.totalPrice, 5500);
      expect(stats.averagePrice, 1833);
      expect(stats.countsByMonth, [1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 2]);

      final y2025 = computeOverviewStats(genreRecords, year: 2025);
      expect(y2025.count, 2);
      expect(y2025.averagePrice, isNull);
      expect(computeOverviewStats(const []).isEmpty, isTrue);
    });

    testWidgets('ジャンルを切り替えると、そのジャンルの集計だけを出す', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recordsProvider.overrideWith((ref) => Stream.value(genreRecords)),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const InsightsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('すべての年'));
      await tester.pumpAndSettle();
      // 「すべて」はジャンルをまたいだ集計だけ。ランキングは各ジャンルで見る
      expect(find.text('ジャンル別'), findsOneWidget);
      expect(find.text('月別の記録'), findsOneWidget);
      expect(find.text('よく行ったアーティスト'), findsNothing);
      expect(find.text('よく聴いた曲'), findsNothing);
      expect(find.text('よく行った会場'), findsNothing);

      // 内訳の行を押すと、そのジャンルの集計へ移る
      await tester.tap(find.widgetWithText(GroupedRow, '映画'));
      await tester.pumpAndSettle();
      expect(find.text('よく行ったアーティスト'), findsNothing);
      expect(find.text('月別の映画'), findsOneWidget);
      expect(find.text('映画の記録・4本'), findsOneWidget);
      expect(find.text('よく行った映画館'), findsOneWidget);
      expect(find.text('チケット代の合計'), findsOneWidget);
      expect(find.text('Tm1'), findsOneWidget);
      expect(find.text('Tb1'), findsNothing);
      expect(find.text('T1'), findsNothing);

      await tester.tap(genreSegment('本'));
      await tester.pumpAndSettle();
      expect(find.text('月別の本'), findsOneWidget);
      expect(find.text('価格の合計'), findsOneWidget);
      expect(find.text('よく行った映画館'), findsNothing);
      expect(find.text('Tb1'), findsOneWidget);

      await tester.tap(genreSegment('その他'));
      await tester.pumpAndSettle();
      expect(find.text('その他を記録すると、ここに集計が表示されます。'), findsOneWidget);

      await tester.tap(genreSegment('ライブ'));
      await tester.pumpAndSettle();
      expect(find.text('よく行ったアーティスト'), findsOneWidget);

      await tester.tap(genreSegment('すべて'));
      await tester.pumpAndSettle();
      expect(find.text('ジャンル別'), findsOneWidget);
    });
  });
}
