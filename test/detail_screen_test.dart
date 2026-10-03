import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/screens/detail_screen.dart';
import 'package:recolle/features/records/widgets/ticket_stub_card.dart';

class _NoFavorites extends FavoriteArtistsNotifier {
  @override
  Future<List<FavoriteArtist>> build() async => const [];
}

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(view.reset);
  });

  Future<void> pumpDetail(
    WidgetTester tester,
    Record record, {
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isOfflineReadOnlyProvider.overrideWithValue(false),
          favoriteArtistsProvider.overrideWith(_NoFavorites.new),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.darkTheme,
          home: DetailScreen(record: record),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final fullLive = Record(
    id: 'r1',
    type: RecordType.live,
    title: 'ARENA TOUR 2025',
    artistOrAuthor: 'King Gnu',
    date: DateTime(2025, 5, 3),
    openTime: const ClockTime(17, 0),
    startTime: const ClockTime(18, 0),
    endTime: const ClockTime(20, 30),
    venue: '東京ドーム',
    seat: 'アリーナ A5 12列 34番',
    ticketPrice: 12000,
    ticketSource: 'e+',
    setlist: '飛行艇\n白日',
    mcMemo: '最高だった',
  );

  for (final (name, theme) in [
    ('ダーク', AppTheme.darkTheme),
    ('ライト', AppTheme.lightTheme),
  ]) {
    testWidgets('$nameテーマで券面に日時・会場・座席・料金を並べる', (tester) async {
      await pumpDetail(tester, fullLive, theme: theme);

      expect(find.byType(TicketStubCard), findsOneWidget);
      expect(find.text('2025.05.03'), findsOneWidget);
      expect(find.text('SAT'), findsOneWidget);
      for (final text in ['17:00', '18:00', '20:30', '東京ドーム', 'e+']) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('アリーナ A5 12列 34番'), findsOneWidget);
      expect(find.text('¥12,000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('入力のあるセトリ・MCメモだけを出し、未入力の項目は案内にまとめる', (tester) async {
    await pumpDetail(tester, fullLive);

    await tester.scrollUntilVisible(find.text('最高だった'), 200);
    expect(find.text('2曲'), findsOneWidget);
    expect(find.text('白日'), findsOneWidget);
    expect(find.text('未入力'), findsNothing);
    expect(find.text('感想は右上の「編集」から追加できます'), findsOneWidget);
  });

  testWidgets('本は会場・座席・時刻を持たないので、券面は日付と価格だけ', (tester) async {
    await pumpDetail(
      tester,
      Record(
        id: 'b1',
        type: RecordType.book,
        title: '本のタイトル',
        artistOrAuthor: '著者',
        date: DateTime(2025, 1, 1),
        ticketPrice: 1800,
        impressions: '面白かった',
      ),
    );

    expect(find.text('START'), findsNothing);
    expect(find.text('VENUE'), findsNothing);
    expect(find.text('PRICE'), findsOneWidget);
    expect(find.text('価格'), findsOneWidget);
    expect(find.text('SETLIST'), findsNothing);
    expect(find.textContaining('から追加できます'), findsNothing);
  });
}
