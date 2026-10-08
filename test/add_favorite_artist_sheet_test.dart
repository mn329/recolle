import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/add_favorite_artist_sheet.dart';
import 'package:recolle/features/music/data/deezer_client.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:recolle/features/music/screens/artist_detail_screen.dart';
import 'package:recolle/features/records/providers/records_provider.dart';

class _RecordingFavorites extends FavoriteArtistsNotifier {
  final added = <({String name, int? itunesArtistId})>[];

  @override
  Future<List<FavoriteArtist>> build() async => const [];

  @override
  Future<FavoriteArtist> add({
    required String name,
    int? itunesArtistId,
  }) async {
    added.add((name: name, itunesArtistId: itunesArtistId));
    final artist = FavoriteArtist(
      id: 'f${added.length}',
      name: name,
      itunesArtistId: itunesArtistId,
      createdAt: DateTime(2026),
    );
    state = AsyncData([...?state.asData?.value, artist]);
    return artist;
  }
}

const _oneOkRock = ItunesArtist(id: 42, name: 'ONE OK ROCK', genre: 'Rock');

class _FakeItunesClient extends ItunesClient {
  @override
  Future<List<ItunesArtist>> searchArtists(
    String term, {
    int limit = 8,
  }) async =>
      term.toLowerCase().contains('one') ? const [_oneOkRock] : const [];

  @override
  Future<ItunesArtist?> findArtist(String artistName, {int? artistId}) async =>
      _oneOkRock;

  @override
  Future<List<ItunesSong>> topSongs(int artistId, {int limit = 10}) async =>
      const [];

  @override
  Future<String?> findArtistArtwork(String artistName) async => null;
}

DeezerClient _offlineDeezer() => DeezerClient(
  httpClient: MockClient((_) async => http.Response('{"data":[]}', 200)),
);

Future<_RecordingFavorites> _openSheet(WidgetTester tester) async {
  final favorites = _RecordingFavorites();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        favoriteArtistsProvider.overrideWith(() => favorites),
        itunesClientProvider.overrideWithValue(_FakeItunesClient()),
        deezerClientProvider.overrideWithValue(_offlineDeezer()),
        artistArtworkProvider.overrideWith((ref, _) async => null),
        recordsProvider.overrideWith((ref) => Stream.value(const [])),
        isOfflineReadOnlyProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showAddFavoriteArtistSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return favorites;
}

Finder get _searchField => find.byType(CupertinoSearchTextField);

void main() {
  testWidgets('候補を選ぶと詳細を開くだけで、お気に入りには登録しない', (tester) async {
    final favorites = await _openSheet(tester);

    await tester.enterText(_searchField, 'one ok');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ONE OK ROCK'));
    await tester.pumpAndSettle();

    expect(find.byType(ArtistDetailScreen), findsOneWidget);
    expect(find.text('アーティストを追加'), findsNothing);
    expect(favorites.added, isEmpty);
    expect(find.bySemanticsLabel('お気に入りに追加'), findsOneWidget);
  });

  testWidgets('詳細の星を押すと、iTunes のアーティスト ID 付きで登録する', (tester) async {
    final favorites = await _openSheet(tester);

    await tester.enterText(_searchField, 'one ok');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ONE OK ROCK'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('お気に入りに追加'));
    await tester.pumpAndSettle();

    expect(favorites.added, [(name: 'ONE OK ROCK', itunesArtistId: 42)]);
    expect(find.bySemanticsLabel('お気に入りから外す'), findsOneWidget);
  });

  testWidgets('検索キーを押しても、お気に入りには登録しない', (tester) async {
    final favorites = await _openSheet(tester);

    await tester.enterText(_searchField, 'YOASOBI');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(favorites.added, isEmpty);
    expect(find.text('アーティストを追加'), findsOneWidget);
  });

  testWidgets('「〜を追加」を押したときだけ、入力した名前で登録する', (tester) async {
    final favorites = await _openSheet(tester);

    await tester.enterText(_searchField, 'YOASOBI');
    await tester.pumpAndSettle();
    await tester.tap(find.text('「YOASOBI」を追加'));
    await tester.pumpAndSettle();

    expect(favorites.added, [(name: 'YOASOBI', itunesArtistId: null)]);
    expect(find.text('アーティストを追加'), findsNothing);
  });
}
