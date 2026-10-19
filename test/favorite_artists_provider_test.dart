import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/account/providers/auth_providers.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'support/favorite_artists_fakes.dart';

const _albumArtwork = 'https://is1-ssl.mzstatic.com/image/a/400x400bb.jpg';
const _deezerImage = 'https://cdn-images.dzcdn.net/images/artist/x/500x500.jpg';

const _customImage = fakeUploadedImageUrl;
const _oldCustomImage = 'https://img/custom-old';

ProviderContainer _container({
  required FakeFavoriteArtistsRepository repository,
  required FakeArtistArtworkFinder finder,
  MemoryFavoriteArtistsCache? cache,
}) {
  final container = ProviderContainer(
    overrides: favoriteArtistsOverrides(
      repository: repository,
      finder: finder,
      cache: cache,
    ),
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
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist('1', 'Aimer', artworkUrl: _albumArtwork),
        favoriteArtist('2', 'YOASOBI'),
        favoriteArtist('3', 'King Gnu', artworkUrl: _deezerImage),
      ]);
      final finder = FakeArtistArtworkFinder({
        'Aimer': 'https://img/aimer',
        'YOASOBI': 'https://img/yoasobi',
      });
      final cache = MemoryFavoriteArtistsCache();
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
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist('1', 'Aimer', artworkUrl: _albumArtwork),
      ]);
      final finder = FakeArtistArtworkFinder(const {});
      final container = _container(repository: repository, finder: finder);

      await _loaded(container);
      container.invalidate(favoriteArtistsProvider);
      await _loaded(container);

      expect(finder.imageQueries, ['Aimer']);
      expect(repository.artworkUpdates, isEmpty);
    });
  });

  test('追加するときは、見つけた画像を付けて登録する', () async {
    final repository = FakeFavoriteArtistsRepository(const []);
    final container = _container(
      repository: repository,
      finder: FakeArtistArtworkFinder({'Vaundy': 'https://img/vaundy'}),
    );
    await _loaded(container);

    final added = await container
        .read(favoriteArtistsProvider.notifier)
        .add(name: 'Vaundy');

    expect(repository.addedArtworks, ['https://img/vaundy']);
    expect(added.artworkUrl, 'https://img/vaundy');
    expect(container.read(favoriteArtistsProvider).requireValue, [added]);
  });

  group('独自画像', () {
    test('画像を変更すると、アップロードして保存し、自動取得の写真は残す', () async {
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist('1', 'Aimer', artworkUrl: _deezerImage),
      ]);
      final cache = MemoryFavoriteArtistsCache();
      final container = _container(
        repository: repository,
        finder: FakeArtistArtworkFinder(const {}),
        cache: cache,
      );
      await _loaded(container);

      await container
          .read(favoriteArtistsProvider.notifier)
          .changeImage('1', File('/tmp/picked.jpg'));

      expect(repository.uploads, [
        (userId: 'u1', favoriteId: '1', path: '/tmp/picked.jpg'),
      ]);
      expect(repository.customImageUpdates, [('1', _customImage)]);
      final artist = container
          .read(favoriteArtistsProvider)
          .requireValue
          .single;
      expect(artist.customImageUrl, _customImage);
      expect(artist.artworkUrl, _deezerImage);
      expect(artist.displayArtworkUrl, _customImage);
      expect(cache.saved['u1']!.single['custom_image_url'], _customImage);
      expect(repository.deletedImages, isEmpty);
    });

    test('すでに独自画像があるときは、保存できたあとに古い画像を消す', () async {
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist(
          '1',
          'Aimer',
          artworkUrl: _deezerImage,
          customImageUrl: _oldCustomImage,
        ),
      ]);
      final container = _container(
        repository: repository,
        finder: FakeArtistArtworkFinder(const {}),
      );
      await _loaded(container);

      await container
          .read(favoriteArtistsProvider.notifier)
          .changeImage('1', File('/tmp/picked.jpg'));

      expect(repository.deletedImages, [_oldCustomImage]);
      expect(
        container
            .read(favoriteArtistsProvider)
            .requireValue
            .single
            .customImageUrl,
        _customImage,
      );
    });

    test('古い画像を消せなくても、変更は成功として扱う', () async {
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist('1', 'Aimer', customImageUrl: _oldCustomImage),
      ])..failDeleteImages = true;
      final container = _container(
        repository: repository,
        finder: FakeArtistArtworkFinder(const {}),
      );
      await _loaded(container);

      await container
          .read(favoriteArtistsProvider.notifier)
          .changeImage('1', File('/tmp/picked.jpg'));

      expect(
        container
            .read(favoriteArtistsProvider)
            .requireValue
            .single
            .customImageUrl,
        _customImage,
      );
    });

    test('保存に失敗したら、上げた画像を消して、表示は変えずにエラーを返す', () async {
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist('1', 'Aimer', customImageUrl: _oldCustomImage),
      ])..failSetCustomImage = true;
      final cache = MemoryFavoriteArtistsCache();
      final container = _container(
        repository: repository,
        finder: FakeArtistArtworkFinder(const {}),
        cache: cache,
      );
      await _loaded(container);
      cache.saved.clear();

      await expectLater(
        container
            .read(favoriteArtistsProvider.notifier)
            .changeImage('1', File('/tmp/picked.jpg')),
        throwsException,
      );

      expect(repository.deletedImages, [_customImage]);
      expect(
        container
            .read(favoriteArtistsProvider)
            .requireValue
            .single
            .customImageUrl,
        _oldCustomImage,
      );
      expect(cache.saved, isEmpty);
    });

    test('元の写真に戻すと、独自画像を外して Storage の画像を消す', () async {
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist(
          '1',
          'Aimer',
          artworkUrl: _deezerImage,
          customImageUrl: _oldCustomImage,
        ),
      ]);
      final cache = MemoryFavoriteArtistsCache();
      final container = _container(
        repository: repository,
        finder: FakeArtistArtworkFinder(const {}),
        cache: cache,
      );
      await _loaded(container);

      await container.read(favoriteArtistsProvider.notifier).resetImage('1');

      expect(repository.customImageUpdates, [('1', null)]);
      expect(repository.deletedImages, [_oldCustomImage]);
      final artist = container
          .read(favoriteArtistsProvider)
          .requireValue
          .single;
      expect(artist.customImageUrl, isNull);
      expect(artist.displayArtworkUrl, _deezerImage);
      expect(cache.saved['u1']!.single['custom_image_url'], isNull);
    });

    test('独自画像がないお気に入りを戻そうとしても、何もしない', () async {
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist('1', 'Aimer', artworkUrl: _deezerImage),
      ]);
      final container = _container(
        repository: repository,
        finder: FakeArtistArtworkFinder(const {}),
      );
      await _loaded(container);

      await container.read(favoriteArtistsProvider.notifier).resetImage('1');

      expect(repository.customImageUpdates, isEmpty);
      expect(repository.deletedImages, isEmpty);
    });

    test('お気に入りから外すと、独自画像も消す', () async {
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist('1', 'Aimer', customImageUrl: _oldCustomImage),
        favoriteArtist('2', 'YOASOBI', artworkUrl: _deezerImage),
      ]);
      final container = _container(
        repository: repository,
        finder: FakeArtistArtworkFinder(const {}),
      );
      await _loaded(container);

      await container.read(favoriteArtistsProvider.notifier).remove('1');

      expect(repository.deletedImages, [_oldCustomImage]);
      expect(
        [
          for (final f in container.read(favoriteArtistsProvider).requireValue)
            f.id,
        ],
        ['2'],
      );
    });

    test('自動の画像の置き換えが、独自画像を上書きしない', () async {
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist('1', 'Aimer', customImageUrl: _oldCustomImage),
      ]);
      final container = _container(
        repository: repository,
        finder: FakeArtistArtworkFinder({'Aimer': 'https://img/aimer'}),
      );

      await _loaded(container);

      final artist = container
          .read(favoriteArtistsProvider)
          .requireValue
          .single;
      expect(artist.artworkUrl, 'https://img/aimer');
      expect(artist.customImageUrl, _oldCustomImage);
      expect(artist.displayArtworkUrl, _oldCustomImage);
    });
  });
}
