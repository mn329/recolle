import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/add_favorite_artist_sheet.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';

class _RecordingFavorites extends FavoriteArtistsNotifier {
  final added = <String>[];

  @override
  Future<List<FavoriteArtist>> build() async => const [];

  @override
  Future<FavoriteArtist> add({
    required String name,
    int? itunesArtistId,
    String? artworkUrl,
  }) async {
    added.add(name);
    return FavoriteArtist(id: 'f1', name: name, createdAt: DateTime(2026));
  }
}

class _NoResultsItunesClient extends ItunesClient {
  @override
  Future<List<ItunesArtist>> searchArtists(String term, {int limit = 8}) async =>
      const [];

  @override
  Future<String?> findArtistArtwork(String artistName) async => null;
}

Future<_RecordingFavorites> _openSheet(WidgetTester tester) async {
  final favorites = _RecordingFavorites();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        favoriteArtistsProvider.overrideWith(() => favorites),
        itunesClientProvider.overrideWithValue(_NoResultsItunesClient()),
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

void main() {
  testWidgets('検索キーを押しても、お気に入りには登録しない', (tester) async {
    final favorites = await _openSheet(tester);

    await tester.enterText(find.byType(CupertinoSearchTextField), 'YOASOBI');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(favorites.added, isEmpty);
    expect(find.text('アーティストを追加'), findsOneWidget);
  });

  testWidgets('「〜を追加」を押したときだけ、入力した名前で登録する', (tester) async {
    final favorites = await _openSheet(tester);

    await tester.enterText(find.byType(CupertinoSearchTextField), 'YOASOBI');
    await tester.pumpAndSettle();
    await tester.tap(find.text('「YOASOBI」を追加'));
    await tester.pumpAndSettle();

    expect(favorites.added, ['YOASOBI']);
    expect(find.text('アーティストを追加'), findsNothing);
  });
}
