import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/data/json_list_file_cache.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/features/account/providers/auth_providers.dart';
import 'package:recolle/features/favorites/data/favorite_artists_repository.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/music/data/artist_artwork_finder.dart';
import 'package:recolle/features/music/data/deezer_client.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

const _albumArtwork = 'https://is1-ssl.mzstatic.com/image/a/400x400bb.jpg';
const _deezerImage = 'https://cdn-images.dzcdn.net/images/artist/x/500x500.jpg';

FavoriteArtist _favorite(String id, String name, {String? artworkUrl}) =>
    FavoriteArtist(
      id: id,
      name: name,
      artworkUrl: artworkUrl,
      createdAt: DateTime(2026),
    );

class _FakeRepository implements FavoriteArtistsRepository {
  _FakeRepository(this.favorites);

  final List<FavoriteArtist> favorites;
  final artworkUpdates = <(String, String)>[];
  final addedArtworks = <String?>[];

  @override
  Future<List<FavoriteArtist>> fetchAll() async => favorites;

  @override
  Future<FavoriteArtist> add({
    required String name,
    int? itunesArtistId,
    String? artworkUrl,
  }) async {
    addedArtworks.add(artworkUrl);
    return _favorite('new', name, artworkUrl: artworkUrl);
  }

  @override
  Future<void> updateArtwork(String id, String artworkUrl) async =>
      artworkUpdates.add((id, artworkUrl));

  @override
  Future<void> remove(String id) async {}
}

class _MemoryCache implements JsonListFileCache {
  @override
  String get fileNamePrefix => 'test';

  final saved = <String, List<Map<String, dynamic>>>{};

  @override
  Future<void> save(String userId, List<Map<String, dynamic>> items) async =>
      saved[userId] = items;

  @override
  Future<List<Map<String, dynamic>>> load(String userId) async =>
      saved[userId] ?? const [];
}

class _FakeFinder extends ArtistArtworkFinder {
  _FakeFinder(this.images)
    : super(deezer: DeezerClient(), itunes: ItunesClient());

  final Map<String, String> images;
  final imageQueries = <String>[];

  @override
  Future<String?> findArtistImage(String artistName) async {
    imageQueries.add(artistName);
    return images[artistName];
  }

  @override
  Future<String?> find(String artistName) async => images[artistName];
}

ProviderContainer _container({
  required _FakeRepository repository,
  required _FakeFinder finder,
  _MemoryCache? cache,
}) {
  final container = ProviderContainer(
    overrides: [
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
      connectivityProvider.overrideWith(
        (ref) => Stream.value(const [ConnectivityResult.wifi]),
      ),
      favoriteArtistsRepositoryProvider.overrideWithValue(repository),
      favoriteArtistsCacheProvider.overrideWithValue(cache ?? _MemoryCache()),
      artistArtworkFinderProvider.overrideWithValue(finder),
    ],
  );
  addTearDown(container.dispose);
  container.listen(favoriteArtistsProvider, (_, _) {});
  return container;
}

Future<List<FavoriteArtist>> _loaded(ProviderContainer container) async {
  await container.read(authUserProvider.future);
  final favorites = await container.read(favoriteArtistsProvider.future);
  await pumpEventQueue();
  return favorites;
}

void main() {
  group('画像の置き換え', () {
    test('画像なし・ジャケットのお気に入りだけを、アーティスト画像に置き換える', () async {
      final repository = _FakeRepository([
        _favorite('1', 'Aimer', artworkUrl: _albumArtwork),
        _favorite('2', 'YOASOBI'),
        _favorite('3', 'King Gnu', artworkUrl: _deezerImage),
      ]);
      final finder = _FakeFinder({
        'Aimer': 'https://img/aimer',
        'YOASOBI': 'https://img/yoasobi',
      });
      final cache = _MemoryCache();
      final container = _container(
        repository: repository,
        finder: finder,
        cache: cache,
      );

      await _loaded(container);

      expect(finder.imageQueries, ['Aimer', 'YOASOBI']);
      expect(repository.artworkUpdates, [
        ('1', 'https://img/aimer'),
        ('2', 'https://img/yoasobi'),
      ]);
      final state = container.read(favoriteArtistsProvider).requireValue;
      expect(
        [for (final f in state) f.artworkUrl],
        ['https://img/aimer', 'https://img/yoasobi', _deezerImage],
      );
      expect(cache.saved['u1']!.first['artwork_url'], 'https://img/aimer');
    });

    test('見つからなかったお気に入りは、再取得しても問い合わせ直さない', () async {
      final repository = _FakeRepository([
        _favorite('1', 'Aimer', artworkUrl: _albumArtwork),
      ]);
      final finder = _FakeFinder(const {});
      final container = _container(repository: repository, finder: finder);

      await _loaded(container);
      container.invalidate(favoriteArtistsProvider);
      await _loaded(container);

      expect(finder.imageQueries, ['Aimer']);
      expect(repository.artworkUpdates, isEmpty);
    });
  });

  test('追加するときは、見つけた画像を付けて登録する', () async {
    final repository = _FakeRepository(const []);
    final container = _container(
      repository: repository,
      finder: _FakeFinder({'Vaundy': 'https://img/vaundy'}),
    );
    await _loaded(container);

    final added = await container
        .read(favoriteArtistsProvider.notifier)
        .add(name: 'Vaundy');

    expect(repository.addedArtworks, ['https://img/vaundy']);
    expect(added.artworkUrl, 'https://img/vaundy');
    expect(container.read(favoriteArtistsProvider).requireValue, [added]);
  });
}
