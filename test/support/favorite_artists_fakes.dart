import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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

/// [FakeFavoriteArtistsRepository.uploadCustomImage] が返す画像の URL。
const fakeUploadedImageUrl = 'https://img/custom-new';

FavoriteArtist favoriteArtist(
  String id,
  String name, {
  String? artworkUrl,
  String? customImageUrl,
}) => FavoriteArtist(
  id: id,
  name: name,
  artworkUrl: artworkUrl,
  customImageUrl: customImageUrl,
  createdAt: DateTime(2026),
);

/// 通信せずに、呼ばれた操作を記録するお気に入りのリポジトリ。
class FakeFavoriteArtistsRepository implements FavoriteArtistsRepository {
  FakeFavoriteArtistsRepository(this.favorites);

  final List<FavoriteArtist> favorites;
  final artworkUpdates = <(String, String)>[];
  final addedArtworks = <String?>[];
  final removedIds = <String>[];
  final uploads = <({String userId, String favoriteId, String path})>[];
  final customImageUpdates = <(String, String?)>[];
  final deletedImages = <String>[];

  /// true なら、DB の更新を失敗させる。
  bool failSetCustomImage = false;

  /// true なら、Storage の画像の削除を失敗させる。
  bool failDeleteImages = false;

  @override
  Future<List<FavoriteArtist>> fetchAll() async => favorites;

  @override
  Future<FavoriteArtist> add({
    required String name,
    int? itunesArtistId,
    String? artworkUrl,
  }) async {
    addedArtworks.add(artworkUrl);
    return favoriteArtist('new', name, artworkUrl: artworkUrl);
  }

  @override
  Future<void> updateArtwork(String id, String artworkUrl) async =>
      artworkUpdates.add((id, artworkUrl));

  @override
  Future<void> remove(String id) async => removedIds.add(id);

  @override
  Future<String> uploadCustomImage({
    required String userId,
    required String favoriteId,
    required File file,
  }) async {
    uploads.add((userId: userId, favoriteId: favoriteId, path: file.path));
    return fakeUploadedImageUrl;
  }

  @override
  Future<void> setCustomImage(String id, String? imageUrl) async {
    if (failSetCustomImage) throw Exception('update failed');
    customImageUpdates.add((id, imageUrl));
  }

  @override
  Future<void> deleteCustomImages(List<String> urls) async {
    if (failDeleteImages) throw Exception('delete failed');
    deletedImages.addAll(urls);
  }
}

class MemoryFavoriteArtistsCache implements JsonListFileCache {
  @override
  String get fileNamePrefix => 'test';

  final saved = <String, List<Map<String, dynamic>>>{};

  @override
  Future<void> save(String userId, List<Map<String, dynamic>> items) async =>
      saved[userId] = items;

  @override
  Future<void> delete(String userId) async => saved.remove(userId);

  @override
  Future<List<Map<String, dynamic>>> load(String userId) async =>
      saved[userId] ?? const [];
}

class FakeArtistArtworkFinder extends ArtistArtworkFinder {
  FakeArtistArtworkFinder(this.images)
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

/// ログイン済み（ユーザー ID は `u1`）で、お気に入りを偽のリポジトリから読む設定。既定ではオンライン。
List<Override> favoriteArtistsOverrides({
  required FakeFavoriteArtistsRepository repository,
  required FakeArtistArtworkFinder finder,
  MemoryFavoriteArtistsCache? cache,
  List<ConnectivityResult> connectivity = const [ConnectivityResult.wifi],
}) => [
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
  connectivityProvider.overrideWith((ref) => Stream.value(connectivity)),
  favoriteArtistsRepositoryProvider.overrideWithValue(repository),
  favoriteArtistsCacheProvider.overrideWithValue(
    cache ?? MemoryFavoriteArtistsCache(),
  ),
  artistArtworkFinderProvider.overrideWithValue(finder),
];
