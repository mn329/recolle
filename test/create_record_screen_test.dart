import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/account/providers/auth_providers.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/music/data/concert_discovery_client.dart';
import 'package:recolle/features/music/data/deezer_client.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/data/setlistfm_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:recolle/features/records/data/records_repository.dart';
import 'package:recolle/features/records/data/venue_search_client.dart';
import 'package:recolle/features/records/data/work_search_client.dart';
import 'package:recolle/features/records/field_suggestions.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/providers/venue_search_provider.dart';
import 'package:recolle/features/records/providers/work_search_provider.dart';
import 'package:recolle/features/records/screens/create_record_screen.dart';
import 'package:recolle/features/records/ticket_mail_parser.dart';
import 'package:recolle/features/records/widgets/music_suggestions.dart';
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

class _FakeSetlistFmClient extends SetlistFmClient {
  _FakeSetlistFmClient(this.byTourName)
    : super(FunctionsClient('http://localhost', {}));

  /// ツアー名で検索したときの結果。
  final Map<String, List<SetlistSummary>> byTourName;
  final tourQueries = <String>[];

  @override
  Future<List<SetlistSummary>> search({
    required String artistName,
    String? tourName,
    bool includeEmpty = false,
    int pages = 1,
  }) async {
    if (tourName != null) tourQueries.add(tourName);
    return byTourName[tourName] ?? const [];
  }
}

class _FakeItunesClient extends ItunesClient {
  _FakeItunesClient(this.japaneseTitles, {this.fails = false});

  final Map<String, String> japaneseTitles;
  final bool fails;
  final requests = <({String artist, List<String> titles})>[];
  final prefetched = <String>[];

  @override
  Future<void> prefetchSongCatalog(String artistName) async =>
      prefetched.add(artistName);

  @override
  Future<Map<String, String>> localizeSongTitles({
    required String artistName,
    required List<String> titles,
    int maxIndividualLookups = 6,
  }) async {
    requests.add((artist: artistName, titles: titles));
    if (fails) throw Exception('network down');
    return {
      for (final t in titles)
        if (japaneseTitles[t] case final ja?) t: ja,
    };
  }

  @override
  Future<ItunesArtist?> findArtist(String artistName, {int? artistId}) async =>
      ItunesArtist(id: 1, name: artistName);

  @override
  Future<List<ItunesSong>> topSongs(int artistId, {int limit = 10}) async => [
    const ItunesSong(id: 11, title: 'アイドル', artistName: 'YOASOBI'),
    const ItunesSong(id: 12, title: '夜に駆ける', artistName: 'YOASOBI'),
  ];
}

class _FakeWorkSearchClient extends WorkSearchClient {
  _FakeWorkSearchClient() : super(FunctionsClient('http://localhost', {}));

  @override
  Future<List<WorkSuggestion>> searchBooks(String term) async => const [
    WorkSuggestion(title: 'ノルウェイの森', creator: '村上春樹', year: 2018),
  ];

  @override
  Future<List<WorkSuggestion>> searchMovies(String term) async => const [];
}

/// 会場の地図検索は使わない（Supabase に問い合わせない）。
class _FakeVenueSearchClient extends VenueSearchClient {
  _FakeVenueSearchClient() : super(FunctionsClient('http://localhost', {}));

  @override
  Future<List<VenueSuggestion>> search(
    String term, {
    String? sessionToken,
  }) async => const [];
}

class _FakeRecordsRepository implements RecordsRepository {
  final inserted = <Map<String, dynamic>>[];

  @override
  Future<Record> insertRecord(Map<String, dynamic> row) async {
    inserted.add(row);
    return Record.fromJson({...row, 'id': 'new'});
  }

  @override
  Future<Record> updateRecord(String id, Map<String, dynamic> row) async =>
      Record.fromJson({...row, 'id': id});

  @override
  Future<String> uploadTicketImage({
    required String userId,
    required File file,
  }) async => '';

  @override
  Future<void> deleteTicketImages(List<String> urls) async {}

  @override
  Future<void> deleteRecord(String id) async {}
}

/// 作成画面が閉じるときに返した記録。
Record? _savedResult;

Future<void> _pumpScreen(
  WidgetTester tester, {
  Record? recordToEdit,
  TicketMailInfo? prefill,
  List<SetlistSummary> setlists = const [],
  List<Record> records = const [],
  ConcertDiscoveryClient? discoveryClient,
  SetlistFmClient? setlistFmClient,
  ItunesClient? itunesClient,
  _FakeRecordsRepository? repository,
}) async {
  _savedResult = null;
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        favoriteArtistsProvider.overrideWith(_NoFavorites.new),
        recentSetlistsProvider.overrideWith((ref, _) async => setlists),
        setlistFmClientProvider.overrideWithValue(
          setlistFmClient ?? _FakeSetlistFmClient(const {}),
        ),
        itunesClientProvider.overrideWithValue(
          itunesClient ?? _FakeItunesClient(const {}),
        ),
        deezerClientProvider.overrideWithValue(
          DeezerClient(
            httpClient: MockClient(
              (_) async => http.Response('{"data":[]}', 200),
            ),
          ),
        ),
        recordsProvider.overrideWith((ref) => Stream.value(records)),
        concertDiscoveryClientProvider.overrideWithValue(
          discoveryClient ?? _FakeDiscoveryClient(const []),
        ),
        workSearchClientProvider.overrideWithValue(_FakeWorkSearchClient()),
        venueSearchClientProvider.overrideWithValue(_FakeVenueSearchClient()),
        authUserProvider.overrideWith(
          (ref) => Stream.value(
            User(
              id: 'u1',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: '2026-01-01T00:00:00Z',
            ),
          ),
        ),
        recordsRepositoryProvider.overrideWithValue(
          repository ?? _FakeRecordsRepository(),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: CupertinoButton(
                onPressed: () async {
                  _savedResult = await Navigator.push<Record>(
                    context,
                    CupertinoPageRoute<Record>(
                      builder: (_) => CreateRecordScreen(
                        recordToEdit: recordToEdit,
                        prefill: prefill,
                      ),
                    ),
                  );
                },
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

  testWidgets('会場・取得元の欄に触れると候補を出し、押すとその値を入れる', (tester) async {
    await _pumpScreen(
      tester,
      records: [
        Record(
          id: 'old',
          type: RecordType.live,
          title: '前のツアー',
          artistOrAuthor: 'YOASOBI',
          date: DateTime(2025, 5, 1),
          venue: 'Zepp Shinjuku',
        ),
      ],
    );

    final venue = _field('会場');
    await tester.enterText(venue, 'zepp');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CapsuleChip, 'Zepp Shinjuku'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CupertinoTextField>(venue).controller!.text,
      'Zepp Shinjuku',
    );

    // 取得元は一覧（ホイール）から選ぶ。開いて回し、「完了」で閉じると選んだ値が行に出る
    await tester.ensureVisible(find.text('チケット取得元'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('チケット取得元'));
    await tester.pumpAndSettle();
    final index = commonSources(RecordType.live).indexOf('ローチケ');
    expect(index, isNonNegative);
    // ホイールの先頭は「未設定」なので、定番の n 番目は n + 1 行目
    await tester.drag(
      find.byType(CupertinoPicker),
      Offset(0, -36.0 * (index + 1)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();
    expect(find.text('ローチケ'), findsOneWidget);
  });

  testWidgets('追加を押すと記録を登録し、登録した記録を返して閉じる', (tester) async {
    final repository = _FakeRecordsRepository();
    await _pumpScreen(tester, repository: repository);
    await tester.enterText(_field('アーティスト'), 'YOASOBI');
    await tester.enterText(_field('公演名・ツアー名'), 'ZEPP TOUR');
    await tester.enterText(_field('あとで読み返したいことを自由に'), 'よかった');
    await tester.pump();

    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(repository.inserted.single['user_id'], 'u1');
    expect(repository.inserted.single['impressions'], 'よかった');
    expect(_savedResult?.id, 'new');
    expect(_savedResult?.artistOrAuthor, 'YOASOBI');
    expect(_savedResult?.title, 'ZEPP TOUR');
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

  testWidgets('本の書名を入力すると候補を出し、選ぶと書名と著者を入れる', (tester) async {
    await _pumpScreen(tester);
    await tester.tap(find.text('本'));
    await tester.pumpAndSettle();

    await tester.tap(_field('書名'));
    await tester.enterText(_field('書名'), 'ノルウェイ');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('村上春樹 · 2018年'), findsOneWidget);
    await tester.tap(find.text('ノルウェイの森'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<CupertinoTextField>(_field('ノルウェイの森')).controller!.text,
      'ノルウェイの森',
    );
    expect(
      tester.widget<CupertinoTextField>(_field('村上春樹')).controller!.text,
      '村上春樹',
    );
    // 選んだ後は同じ候補を出し直さない
    expect(find.text('村上春樹 · 2018年'), findsNothing);
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

  testWidgets('時刻のホイールを開いたまま会場をタップすると、ホイールを閉じて会場を入力できる', (tester) async {
    await _pumpScreen(tester);
    await tester.ensureVisible(find.text('終演'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('終演'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);

    await Scrollable.ensureVisible(
      tester.element(_field('会場')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(_field('会場'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoDatePicker), findsNothing);
    expect(tester.testTextInput.isVisible, isTrue);
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(
      focused != null &&
          find
              .descendant(
                of: _field('会場'),
                matching: find.byWidget(focused.widget),
              )
              .evaluate()
              .isNotEmpty,
      isTrue,
    );
  });

  testWidgets('セトリの 1 曲目の欄に触れると、入力前でもアーティストの人気曲を候補に出す', (tester) async {
    await _pumpScreen(tester);
    await tester.enterText(_field('アーティスト'), 'YOASOBI');
    await tester.pump();

    await tester.ensureVisible(_field('1曲目の曲名を入力'));
    await tester.pumpAndSettle();
    await tester.showKeyboard(_field('1曲目の曲名を入力'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(CupertinoButton, 'アイドル'), findsOneWidget);
    expect(find.widgetWithText(CupertinoButton, '夜に駆ける'), findsOneWidget);
  });

  group('セトリの区切りと貼り付け', () {
    testWidgets('複数行を貼り付けると 1 行ずつ追加し、アンコールは番号なしの区切りにする', (tester) async {
      final repository = _FakeRecordsRepository();
      await _pumpScreen(tester, repository: repository);
      await tester.enterText(_field('アーティスト'), 'YOASOBI');
      await tester.enterText(_field('公演名・ツアー名'), 'ZEPP TOUR');
      await tester.enterText(_field('1曲目の曲名を入力'), '1. 夜に駆ける\n2. 群青\nEN1. アイドル');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(find.text('3曲'), findsOneWidget);
      // 区切りには番号を振らないので、追加欄の次の番号は 04
      expect(find.text('04'), findsOneWidget);
      expect(find.text('05'), findsNothing);
      expect(_field('次の曲を追加'), findsOneWidget);

      await tester.tap(find.text('追加'));
      await tester.pumpAndSettle();
      expect(
        repository.inserted.single['setlist'],
        '夜に駆ける\n群青\n--- アンコール ---\nアイドル',
      );
    });

    testWidgets('ボタンでリハ・本番・MC・アンコールを入れ、曲数には数えない', (tester) async {
      final repository = _FakeRecordsRepository();
      await _pumpScreen(tester, repository: repository);
      await tester.enterText(_field('アーティスト'), 'YOASOBI');
      await tester.enterText(_field('公演名・ツアー名'), 'ZEPP TOUR');
      await tester.enterText(_field('1曲目の曲名を入力'), '群青');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      Finder button(String label) =>
          find.widgetWithText(CupertinoButton, label);
      await tester.ensureVisible(button('リハ'));
      await tester.tap(button('リハ'));
      await tester.pump();
      // リハを入れたら、次は本番を入れるボタンになる
      expect(button('リハ'), findsNothing);
      await tester.tap(button('本番'));
      await tester.pump();
      expect(button('本番'), findsNothing);
      await tester.tap(button('MC'));
      await tester.tap(button('アンコール'));
      await tester.tap(button('アンコール'));
      await tester.pumpAndSettle();

      expect(find.text('1曲'), findsOneWidget);
      await tester.tap(find.text('追加'));
      await tester.pumpAndSettle();
      expect(
        repository.inserted.single['setlist'],
        '--- リハ ---\n群青\n--- 本番 ---\nMC\n--- アンコール ---\n--- アンコール2 ---',
      );
    });
  });

  testWidgets('曲をつまむと強め、ほかの曲をまたぐたびに軽く、離すと軽く振動する', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pumpScreen(tester);
    await tester.enterText(_field('1曲目の曲名を入力'), '群青\n怪物\nアイドル');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    haptics.clear();

    final handle = find.byIcon(CupertinoIcons.line_horizontal_3).first;
    await tester.ensureVisible(handle);
    await tester.pumpAndSettle();
    final rowHeight = tester.getSize(find.byType(Dismissible).first).height;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, rowHeight * 0.25));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // 1 曲目を 3 曲目の位置まで動かしたので、2 曲をまたぐ
    expect(haptics, [
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
    ]);
  });

  group('対バン・フェス', () {
    testWidgets('対バンにすると、入力済みのアーティストとセトリをお目当ての出演者として引き継ぐ', (tester) async {
      await _pumpScreen(tester);
      await tester.enterText(_field('アーティスト'), 'sumika');
      await tester.enterText(_field('1曲目の曲名を入力'), 'Lovers');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      // 入力欄に残るフォーカスで人気曲の候補が出て、画面がそちらへスクロールするため外す
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('対バン'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('対バン'));
      await tester.pumpAndSettle();

      expect(_field('アーティスト'), findsNothing);
      expect(_field('イベント名・対バン名'), findsOneWidget);
      final firstAct = tester.widget<CupertinoTextField>(_field('1組目の出演者'));
      expect(firstAct.controller!.text, 'sumika');
      expect(find.byIcon(CupertinoIcons.star_fill), findsOneWidget);
      expect(find.text('1曲'), findsOneWidget);
      // 対バンは最初から 2 組分の欄を出す
      expect(_field('2組目の出演者'), findsOneWidget);

      await tester.ensureVisible(find.text('出演者を追加'));
      await tester.tap(find.text('出演者を追加'));
      await tester.pumpAndSettle();
      expect(_field('3組目の出演者'), findsOneWidget);
    });

    testWidgets('お目当ては 1 組だけで、別の ★ を押すとそちらへ移り、同じ ★ で外れる', (tester) async {
      await _pumpScreen(tester);
      await tester.ensureVisible(find.text('対バン'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('対バン'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('1組目の出演者'), 'sumika');
      await tester.enterText(_field('2組目の出演者'), 'Mrs. GREEN APPLE');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(_field('1組目の出演者'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(CupertinoIcons.star).first);
      await tester.pump();
      expect(find.byIcon(CupertinoIcons.star_fill), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.star));
      await tester.pump();
      expect(find.byIcon(CupertinoIcons.star_fill), findsOneWidget);
      final secondRow = find.ancestor(
        of: _field('2組目の出演者'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(
          of: secondRow.first,
          matching: find.byIcon(CupertinoIcons.star_fill),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(CupertinoIcons.star_fill));
      await tester.pump();
      expect(find.byIcon(CupertinoIcons.star_fill), findsNothing);
    });

    testWidgets('出演者のセトリはカードの中で開閉する', (tester) async {
      await _pumpScreen(tester);
      await tester.tap(find.text('対バン'));
      await tester.pumpAndSettle();
      expect(_field('1曲目の曲名を入力'), findsNothing);

      await tester.tap(find.text('セットリスト').first);
      await tester.pumpAndSettle();
      expect(_field('1曲目の曲名を入力'), findsOneWidget);

      await tester.tap(find.text('セットリスト').first);
      await tester.pumpAndSettle();
      expect(_field('1曲目の曲名を入力'), findsNothing);
    });

    testWidgets('出演者の名前がなければ「出演者」を必須として案内する', (tester) async {
      await _pumpScreen(tester);
      await tester.tap(find.text('フェス'));
      await tester.pumpAndSettle();

      expect(find.text('出演者とイベント名・フェス名は必須です。'), findsOneWidget);
      expect(find.text('最終日'), findsOneWidget);

      await tester.enterText(_field('1組目の出演者'), 'サカナクション');
      await tester.enterText(_field('イベント名・フェス名'), 'ROCK IN JAPAN');
      await tester.pump();
      expect(find.textContaining('必須です'), findsNothing);
      expect(_navButton(tester, '追加').onPressed, isNotNull);
    });

    testWidgets('フェスの編集では出演者・お目当て・最終日を表示し、読み込んだだけでは未変更のまま', (tester) async {
      await _pumpScreen(
        tester,
        recordToEdit: Record(
          id: 'f1',
          type: RecordType.live,
          title: 'ROCK IN JAPAN',
          artistOrAuthor: 'サカナクション',
          date: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 2),
          eventFormat: EventFormat.festival,
          acts: const [
            RecordAct(artist: 'サカナクション', songs: ['新宝島'], isMain: true, day: 1),
            RecordAct(artist: 'sumika', day: 2),
          ],
        ),
      );

      expect(find.text('2組'), findsOneWidget);
      expect(find.text('サカナクション'), findsWidgets);
      expect(find.text('sumika'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.star_fill), findsOneWidget);
      expect(find.text('最終日'), findsOneWidget);
      expect(find.text('2026年08月02日 (日)'), findsOneWidget);
      // 2 日間なので日ごとに出演者を分ける
      expect(find.text('DAY 1'), findsOneWidget);
      expect(find.text('DAY 2'), findsOneWidget);
      expect(find.text('1日目の出演者を追加'), findsOneWidget);
      expect(find.text('2日目の出演者を追加'), findsOneWidget);

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });
  });

  group('公演名の候補', () {
    final setlist = SetlistSummary(
      id: 's1',
      eventDate: DateTime(2025, 5, 3),
      artistName: 'King Gnu',
      venueName: '東京ドーム',
      cityName: 'Tokyo',
      tourName: 'ARENA TOUR 2025',
      songs: const ['Hikoutei', '白日'],
    );

    List<String?> fieldTexts(WidgetTester tester) => [
      for (final field in tester.widgetList<CupertinoTextField>(
        find.byType(CupertinoTextField),
      ))
        field.controller?.text,
    ];

    testWidgets('setlist.fm の公演を選ぶと公演名・日付・会場・日本語化したセトリを入れる', (tester) async {
      final itunes = _FakeItunesClient(const {'Hikoutei': '飛行艇'});
      await _pumpScreen(tester, setlists: [setlist], itunesClient: itunes);
      await tester.enterText(_field('アーティスト'), 'King Gnu');
      await tester.showKeyboard(_field('公演名・ツアー名'));
      await tester.pumpAndSettle();

      expect(find.text('ARENA TOUR 2025'), findsOneWidget);
      // 選ぶ前から、曲名の日本語化に使うカタログを読み始めている
      expect(itunes.prefetched, ['King Gnu']);
      await tester.tap(find.text('ARENA TOUR 2025'));
      await tester.pumpAndSettle();

      expect(fieldTexts(tester), containsAll(['ARENA TOUR 2025', '東京ドーム']));
      expect(fieldTexts(tester), containsAll(['飛行艇', '白日']));
      expect(fieldTexts(tester), isNot(contains('Hikoutei')));
      expect(itunes.requests.single.artist, 'King Gnu');
      expect(itunes.requests.single.titles, ['Hikoutei', '白日']);
      expect(find.text('2曲'), findsOneWidget);
      expect(find.text('2025年05月03日 (土)'), findsOneWidget);
      expect(find.text('これからの公演を探す'), findsNothing);
    });

    testWidgets('曲名の日本語化に失敗しても、元の表記でセトリを入れる', (tester) async {
      await _pumpScreen(
        tester,
        setlists: [setlist],
        itunesClient: _FakeItunesClient(const {}, fails: true),
      );
      await tester.enterText(_field('アーティスト'), 'King Gnu');
      await tester.showKeyboard(_field('公演名・ツアー名'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ARENA TOUR 2025'));
      await tester.pumpAndSettle();

      expect(fieldTexts(tester), containsAll(['Hikoutei', '白日']));
      expect(find.text('2曲'), findsOneWidget);
    });

    testWidgets('入力した文字で候補を絞り込み、一致があれば setlist.fm は呼ばない', (tester) async {
      final client = _FakeSetlistFmClient(const {});
      await _pumpScreen(
        tester,
        setlistFmClient: client,
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
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('CEREMONY'), findsOneWidget);
      expect(find.text('ARENA TOUR 2025'), findsNothing);
      expect(client.tourQueries, isEmpty);
    });

    testWidgets('直近の公演にないツアーも、入力した名前で setlist.fm から探す', (tester) async {
      final client = _FakeSetlistFmClient({
        'dome': [
          SetlistSummary(
            id: 's9',
            eventDate: DateTime(2019, 12, 1),
            artistName: 'King Gnu',
            venueName: '東京ドーム',
            cityName: 'Tokyo',
            tourName: 'Sympa Tour',
            songs: const [],
          ),
        ],
      });
      await _pumpScreen(tester, setlists: [setlist], setlistFmClient: client);
      await tester.enterText(_field('アーティスト'), 'King Gnu');
      await tester.enterText(_field('公演名・ツアー名'), 'do');
      await tester.pumpAndSettle();
      await tester.enterText(_field('公演名・ツアー名'), 'dome');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // 2 文字では検索せず、名前に「dome」を含まない結果も setlist.fm の一致として出す
      expect(client.tourQueries, ['dome']);
      expect(find.text('Sympa Tour'), findsOneWidget);
      expect(find.text('ARENA TOUR 2025'), findsNothing);
    });

    testWidgets('一致する候補がなくなっても候補欄を閉じず、検索中と結果を案内する', (tester) async {
      await _pumpScreen(tester, setlists: [setlist]);
      await tester.enterText(_field('アーティスト'), 'King Gnu');
      await tester.enterText(_field('公演名・ツアー名'), 'ar');
      await tester.pumpAndSettle();
      expect(find.text('ARENA TOUR 2025'), findsOneWidget);

      await tester.enterText(_field('公演名・ツアー名'), 'xy');
      await tester.pumpAndSettle();
      expect(find.textContaining('一致する公演はありません'), findsOneWidget);

      await tester.enterText(_field('公演名・ツアー名'), 'xyz');
      await tester.pump();
      // 入力が止まるのを待っている間も、候補欄は読み込み中として残る
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('見つかりませんでした'), findsOneWidget);
    });

    testWidgets('候補が多いときは一覧の高さを抑えてスクロールできる', (tester) async {
      await _pumpScreen(
        tester,
        setlists: [
          for (var i = 0; i < 15; i++)
            SetlistSummary(
              id: 's$i',
              eventDate: DateTime(2025, 1, i + 1),
              artistName: 'King Gnu',
              venueName: '会場$i',
              cityName: 'Tokyo',
              tourName: 'TOUR $i',
              songs: const [],
            ),
        ],
      );
      await tester.enterText(_field('アーティスト'), 'King Gnu');
      await tester.showKeyboard(_field('公演名・ツアー名'));
      await tester.pumpAndSettle();

      final list = find.descendant(
        of: find.byType(ConcertSuggestions),
        matching: find.byType(ListView),
      );
      expect(tester.getSize(list).height, lessThanOrEqualTo(260));
      expect(find.text('TOUR 14'), findsNothing);

      await tester.drag(list, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('TOUR 14'), findsOneWidget);
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
