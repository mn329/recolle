import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/music/data/concert_discovery_client.dart';
import 'package:recolle/features/music/data/setlistfm_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/screens/create_record_screen.dart';
import 'package:recolle/features/records/ticket_mail_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _NoFavorites extends FavoriteArtistsNotifier {
  @override
  Future<List<FavoriteArtist>> build() async => const [];
}

class _FakeDiscoveryClient extends ConcertDiscoveryClient {
  _FakeDiscoveryClient(this.concerts)
    : super(FunctionsClient('http://localhost', {}));

  final List<DiscoveredConcert> concerts;
  int calls = 0;

  @override
  Future<ConcertDiscoveryResult> discover(String artistName) async {
    calls++;
    return ConcertDiscoveryResult(
      concerts: concerts,
      sources: const [],
      fetchedAt: DateTime(2026, 9, 27),
    );
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  Record? recordToEdit,
  TicketMailInfo? prefill,
  List<SetlistSummary> setlists = const [],
  List<Record> records = const [],
  ConcertDiscoveryClient? discoveryClient,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        favoriteArtistsProvider.overrideWith(_NoFavorites.new),
        recentSetlistsProvider.overrideWith((ref, _) async => setlists),
        recordsProvider.overrideWith((ref) => Stream.value(records)),
        concertDiscoveryClientProvider.overrideWithValue(
          discoveryClient ?? _FakeDiscoveryClient(const []),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: CupertinoButton(
                onPressed: () => Navigator.push(
                  context,
                  CupertinoPageRoute<void>(
                    builder: (_) => CreateRecordScreen(
                      recordToEdit: recordToEdit,
                      prefill: prefill,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _field(String placeholder) =>
    find.widgetWithText(CupertinoTextField, placeholder);

NavBarTextButton _navButton(WidgetTester tester, String label) => tester
    .widget<NavBarTextButton>(find.widgetWithText(NavBarTextButton, label));

void main() {
  testWidgets('必須項目が揃うまで追加ボタンは無効で、足りない項目を案内する', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('新規記録'), findsOneWidget);
    expect(find.text('アーティストと公演名・ツアー名は必須です。'), findsOneWidget);
    expect(_navButton(tester, '追加').onPressed, isNull);

    await tester.enterText(_field('アーティスト'), 'YOASOBI');
    await tester.enterText(_field('公演名・ツアー名'), 'ZEPP TOUR');
    await tester.pump();

    expect(find.textContaining('必須です'), findsNothing);
    expect(_navButton(tester, '追加').onPressed, isNotNull);
  });

  testWidgets('種別に応じて入力欄の呼び方とライブ専用欄が切り替わる', (tester) async {
    await _pumpScreen(tester);
    expect(find.text('セットリスト'), findsOneWidget);
    expect(find.text('MCメモ'), findsOneWidget);

    await tester.tap(find.text('本'));
    await tester.pumpAndSettle();

    expect(_field('書名'), findsOneWidget);
    expect(_field('著者'), findsOneWidget);
    expect(find.text('セットリスト'), findsNothing);
    expect(find.text('MCメモ'), findsNothing);
    expect(find.text('購入情報'), findsOneWidget);
    expect(_field('価格'), findsOneWidget);
    expect(_field('座席（G-12 など）'), findsNothing);
  });

  testWidgets('映画の編集では、保存済みの映画館・座席・料金・上映時刻を表示する', (tester) async {
    await _pumpScreen(
      tester,
      recordToEdit: Record(
        id: 'm1',
        type: RecordType.movie,
        title: 'ルックバック',
        artistOrAuthor: '押山清高',
        date: DateTime(2026, 11, 3),
        ticketImageUrl: '',
        venue: 'TOHOシネマズ 新宿',
        seat: 'G-12',
        ticketPrice: 2000,
        startTime: const ClockTime(20, 15),
        endTime: const ClockTime(22, 0),
      ),
    );

    expect(find.text('上映・チケット'), findsOneWidget);
    expect(find.text('開場'), findsNothing);
    expect(find.text('上映開始'), findsOneWidget);
    expect(find.text('20:15'), findsOneWidget);
    expect(find.text('上映終了'), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('TOHOシネマズ 新宿'), findsOneWidget);
    expect(find.text('G-12'), findsOneWidget);
    expect(find.text('2000'), findsOneWidget);
    // 読み込んだだけでは未変更のまま（閉じても破棄の確認が出ない）
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('入力途中で閉じると破棄の確認を出し、続けるを選ぶと画面に留まる', (tester) async {
    await _pumpScreen(tester);
    await tester.enterText(_field('あとで読み返したいことを自由に'), 'よかった');
    await tester.pump();

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(find.text('記録を破棄'), findsOneWidget);

    await tester.tap(find.text('編集を続ける'));
    await tester.pumpAndSettle();
    expect(find.text('新規記録'), findsOneWidget);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('記録を破棄'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('未変更なら確認なしで閉じられる', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('編集時は既存のセトリを曲数付きで表示する', (tester) async {
    await _pumpScreen(
      tester,
      recordToEdit: Record(
        id: 'r1',
        type: RecordType.live,
        title: 'TOUR',
        artistOrAuthor: 'YOASOBI',
        date: DateTime(2026, 9, 1),
        ticketImageUrl: '',
        setlist: 'アイドル\n祝福',
      ),
    );

    expect(find.text('記録を編集'), findsOneWidget);
    expect(find.text('2曲'), findsOneWidget);
    expect(find.text('アイドル'), findsOneWidget);
    expect(_navButton(tester, '保存').onPressed, isNotNull);
  });

  testWidgets('メールを貼り付けると公演名・アーティスト・取得元を入力する', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('メールから入力'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(CupertinoTextField).last,
      'ローソンチケットです。\n公演名：YOASOBI DOME LIVE\n出演者：YOASOBI\n公演日：2026/05/03',
    );
    await tester.pump();
    await tester.tap(find.text('読み取る'));
    await tester.pumpAndSettle();

    expect(find.text('メールから入力'), findsOneWidget);
    expect(find.text('YOASOBI DOME LIVE'), findsWidgets);
    expect(find.text('YOASOBI'), findsWidgets);
    expect(find.text('ローチケ'), findsOneWidget);
    expect(_navButton(tester, '追加').onPressed, isNotNull);
  });

  testWidgets('読み取れないメールならシートに留まって案内する', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('メールから入力'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).last, 'こんにちは');
    await tester.pump();
    await tester.tap(find.text('読み取る'));
    await tester.pump();

    expect(find.textContaining('読み取れませんでした'), findsOneWidget);
  });

  testWidgets('公演検索の結果を渡すと、公演名・日時・会場を入れた状態で開く', (tester) async {
    await _pumpScreen(
      tester,
      prefill: TicketMailInfo(
        title: 'ARENA TOUR 2026',
        artist: 'King Gnu',
        date: DateTime(2026, 11, 3),
        venue: '東京ドーム',
        openTime: const ClockTime(17, 0),
        startTime: const ClockTime(18, 0),
      ),
    );

    final filledTexts = [
      for (final field in tester.widgetList<CupertinoTextField>(
        find.byType(CupertinoTextField),
      ))
        field.controller?.text,
    ];
    expect(filledTexts, containsAll(['ARENA TOUR 2026', 'King Gnu', '東京ドーム']));
    expect(find.text('17:00'), findsOneWidget);
    expect(find.text('18:00'), findsOneWidget);
    expect(_navButton(tester, '追加').onPressed, isNotNull);
  });

  group('公演名の候補', () {
    final setlist = SetlistSummary(
      id: 's1',
      eventDate: DateTime(2025, 5, 3),
      artistName: 'King Gnu',
      venueName: '東京ドーム',
      cityName: 'Tokyo',
      tourName: 'ARENA TOUR 2025',
      songs: const ['飛行艇', '白日'],
    );

    List<String?> fieldTexts(WidgetTester tester) => [
      for (final field in tester.widgetList<CupertinoTextField>(
        find.byType(CupertinoTextField),
      ))
        field.controller?.text,
    ];

    testWidgets('setlist.fm の公演を選ぶと公演名・日付・会場・セトリを入れる', (tester) async {
      await _pumpScreen(tester, setlists: [setlist]);
      await tester.enterText(_field('アーティスト'), 'King Gnu');
      await tester.showKeyboard(_field('公演名・ツアー名'));
      await tester.pumpAndSettle();

      expect(find.text('ARENA TOUR 2025'), findsOneWidget);
      await tester.tap(find.text('ARENA TOUR 2025'));
      await tester.pumpAndSettle();

      expect(fieldTexts(tester), containsAll(['ARENA TOUR 2025', '東京ドーム']));
      expect(find.text('2曲'), findsOneWidget);
      expect(find.text('2025年05月03日 (土)'), findsOneWidget);
      expect(find.text('これからの公演を探す'), findsNothing);
    });

    testWidgets('入力した文字で候補を絞り込む', (tester) async {
      await _pumpScreen(
        tester,
        setlists: [
          setlist,
          SetlistSummary(
            id: 's2',
            eventDate: DateTime(2024, 8, 1),
            artistName: 'King Gnu',
            venueName: 'Zepp Haneda',
            cityName: 'Tokyo',
            tourName: 'CEREMONY',
            songs: const [],
          ),
        ],
      );
      await tester.enterText(_field('アーティスト'), 'King Gnu');
      await tester.enterText(_field('公演名・ツアー名'), 'zepp');
      await tester.pumpAndSettle();

      expect(find.text('CEREMONY'), findsOneWidget);
      expect(find.text('ARENA TOUR 2025'), findsNothing);
    });

    testWidgets('これからの公演は押したときだけ探し、選ぶと開演時刻まで入れる', (tester) async {
      final client = _FakeDiscoveryClient([
        DiscoveredConcert(
          title: 'DOME TOUR 2026',
          date: DateTime(2026, 11, 3),
          venue: '京セラドーム大阪',
          openTime: const ClockTime(16, 30),
          startTime: const ClockTime(18, 0),
        ),
      ]);
      await _pumpScreen(tester, discoveryClient: client);
      await tester.enterText(_field('アーティスト'), 'King Gnu');
      await tester.showKeyboard(_field('公演名・ツアー名'));
      await tester.pumpAndSettle();
      expect(client.calls, 0);

      await tester.tap(find.text('これからの公演を探す'));
      await tester.pumpAndSettle();
      expect(client.calls, 1);

      await tester.tap(find.text('DOME TOUR 2026'));
      await tester.pumpAndSettle();

      expect(fieldTexts(tester), containsAll(['DOME TOUR 2026', '京セラドーム大阪']));
      expect(find.text('16:30'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);
    });

    testWidgets('過去の記録からは公演名だけを入れる', (tester) async {
      await _pumpScreen(
        tester,
        records: [
          Record(
            id: 'r1',
            type: RecordType.live,
            title: 'HALL TOUR',
            artistOrAuthor: 'King Gnu',
            date: DateTime(2025, 1, 10),
            ticketImageUrl: '',
            venue: '日本武道館',
          ),
        ],
      );
      await tester.enterText(_field('アーティスト'), 'King Gnu');
      await tester.showKeyboard(_field('公演名・ツアー名'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('HALL TOUR'));
      await tester.pumpAndSettle();

      final texts = fieldTexts(tester);
      expect(texts, contains('HALL TOUR'));
      expect(texts, isNot(contains('日本武道館')));
    });
  });
}
