import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/core/data/json_list_file_cache.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/features/account/providers/auth_providers.dart';
import 'package:recolle/features/favorites/data/favorite_artists_repository.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/music/data/artist_artwork_finder.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final favoriteArtistsRepositoryProvider = Provider<FavoriteArtistsRepository>(
  (ref) => FavoriteArtistsRepository(Supabase.instance.client),
);

/// お気に入りの端末内キャッシュ。ログアウト・アカウント削除のときにも消す。
const favoriteArtistsCacheFile = JsonListFileCache('favorite_artists_cache');

final favoriteArtistsCacheProvider = Provider<JsonListFileCache>(
  (ref) => favoriteArtistsCacheFile,
);

final favoriteArtistsProvider =
    AsyncNotifierProvider<FavoriteArtistsNotifier, List<FavoriteArtist>>(
      FavoriteArtistsNotifier.new,
    );

class FavoriteArtistsNotifier extends AsyncNotifier<List<FavoriteArtist>> {
  String? _userId;

  /// このセッションで画像の置き換えを試したお気に入り。
  /// 見つからなかったものを再取得（接続状態の変化など）のたびに問い合わせないため。
  final _artworkUpgradeAttempted = <String>{};

  @override
  Future<List<FavoriteArtist>> build() async {
    // トークン更新のたびに再取得しないよう、ユーザー ID の変化だけを見る
    final userId = ref.watch(
      authUserProvider.select((u) => u.asData?.value?.id),
    );
    _userId = userId;
    if (userId == null) return const [];

    final online = ref.watch(
      connectivityProvider.select(
        (c) => c.maybeWhen(data: isConnectivityOnline, orElse: () => true),
      ),
    );
    if (!online) {
      final rows = await ref.read(favoriteArtistsCacheProvider).load(userId);
      return [for (final row in rows) FavoriteArtist.fromJson(row)];
    }

    final favorites = await ref
        .read(favoriteArtistsRepositoryProvider)
        .fetchAll();
    await _saveCache(favorites);
    unawaited(_upgradeArtworks(favorites));
    return favorites;
  }

  /// 画像なし・アルバムジャケットで代用しているお気に入りを、アーティスト画像に置き換える。
  /// 以前はアルバムジャケットしか保存していなかったので、その分も順に更新していく。
  Future<void> _upgradeArtworks(List<FavoriteArtist> favorites) async {
    final targets = favorites.where((f) {
      final url = f.artworkUrl;
      return (url == null || ArtistArtworkFinder.isAlbumArtworkFallback(url)) &&
          _artworkUpgradeAttempted.add(f.id);
    }).toList();
    if (targets.isEmpty) return;

    final finder = ref.read(artistArtworkFinderProvider);
    final repository = ref.read(favoriteArtistsRepositoryProvider);
    for (final favorite in targets) {
      final image = await finder.findArtistImage(favorite.name);
      if (image == null || !ref.mounted) continue;
      try {
        await repository.updateArtwork(favorite.id, image);
      } catch (e) {
        debugPrint('Artwork update failed for ${favorite.name}: $e');
        continue;
      }
      final current = state.asData?.value;
      if (current == null || !ref.mounted) return;
      final next = [
        for (final f in current)
          f.id == favorite.id ? f.copyWith(artworkUrl: image) : f,
      ];
      state = AsyncData(next);
      await _saveCache(next);
    }
  }

  /// [name] をお気に入りに追加する。画像はここで探し、見つからなくても登録は続ける。
  Future<FavoriteArtist> add({
    required String name,
    int? itunesArtistId,
  }) async {
    final artworkUrl = await ref.read(artistArtworkFinderProvider).find(name);
    final added = await ref
        .read(favoriteArtistsRepositoryProvider)
        .add(
          name: name,
          itunesArtistId: itunesArtistId,
          artworkUrl: artworkUrl,
        );
    final next = [...?state.asData?.value, added];
    state = AsyncData(next);
    await _saveCache(next);
    return added;
  }

  Future<void> remove(String id) async {
    final current = state.asData?.value ?? const <FavoriteArtist>[];
    final customImageUrl = current
        .where((f) => f.id == id)
        .firstOrNull
        ?.customImageUrl;
    final repository = ref.read(favoriteArtistsRepositoryProvider);
    await repository.remove(id);
    final next = [
      for (final f in current)
        if (f.id != id) f,
    ];
    state = AsyncData(next);
    await _saveCache(next);
    await _deleteImagesQuietly(repository, [?customImageUrl]);
  }

  /// [id] のお気に入りの画像を、[file] に変更する。
  ///
  /// 画像を上げてから保存し、保存できなかったら上げた画像は消す。
  /// 表示が変わるのは保存できたあとだけで、失敗したら今の画像のまま例外を投げる。
  Future<void> changeImage(String id, File file) async {
    final userId = _userId;
    if (userId == null) {
      throw StateError('ログインしていないので、画像を変更できません。');
    }
    final previous = _byId(id)?.customImageUrl;
    final repository = ref.read(favoriteArtistsRepositoryProvider);
    final imageUrl = await repository.uploadCustomImage(
      userId: userId,
      favoriteId: id,
      file: file,
    );
    try {
      await repository.setCustomImage(id, imageUrl);
    } catch (_) {
      await _deleteImagesQuietly(repository, [imageUrl]);
      rethrow;
    }
    await _applyCustomImage(id, imageUrl);
    await _deleteImagesQuietly(repository, [?previous]);
  }

  /// 独自画像を外して、自動取得のアーティスト写真に戻す。独自画像がなければ何もしない。
  Future<void> resetImage(String id) async {
    final previous = _byId(id)?.customImageUrl;
    if (previous == null) return;
    final repository = ref.read(favoriteArtistsRepositoryProvider);
    await repository.setCustomImage(id, null);
    await _applyCustomImage(id, null);
    await _deleteImagesQuietly(repository, [previous]);
  }

  FavoriteArtist? _byId(String id) =>
      state.asData?.value.where((f) => f.id == id).firstOrNull;

  Future<void> _applyCustomImage(String id, String? imageUrl) async {
    final current = state.asData?.value;
    if (current == null || !ref.mounted) return;
    final next = [
      for (final f in current)
        f.id == id ? f.copyWith(customImageUrl: imageUrl) : f,
    ];
    state = AsyncData(next);
    await _saveCache(next);
  }

  /// 使わなくなった画像の削除。失敗しても操作自体は成功なので、ログだけ残す（残った画像は害にならない）。
  Future<void> _deleteImagesQuietly(
    FavoriteArtistsRepository repository,
    List<String> urls,
  ) async {
    if (urls.isEmpty) return;
    try {
      await repository.deleteCustomImages(urls);
    } catch (e) {
      debugPrint('Custom image delete failed: $e');
    }
  }

  Future<void> _saveCache(List<FavoriteArtist> favorites) async {
    final userId = _userId;
    if (userId == null) return;
    // サーバーには反映済みなので、手元のキャッシュに書けなくても操作は成功として扱う
    try {
      await ref.read(favoriteArtistsCacheProvider).save(userId, [
        for (final f in favorites) f.toJson(),
      ]);
    } catch (e) {
      debugPrint('Favorites cache save failed: $e');
    }
  }
}
