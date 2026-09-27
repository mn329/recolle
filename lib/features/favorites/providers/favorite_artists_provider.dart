import 'dart:async';

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

final favoriteArtistsProvider =
    AsyncNotifierProvider<FavoriteArtistsNotifier, List<FavoriteArtist>>(
      FavoriteArtistsNotifier.new,
    );

class FavoriteArtistsNotifier extends AsyncNotifier<List<FavoriteArtist>> {
  static const _cache = JsonListFileCache('favorite_artists_cache');

  String? _userId;

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
      final rows = await _cache.load(userId);
      return [for (final row in rows) FavoriteArtist.fromJson(row)];
    }

    final favorites = await ref
        .read(favoriteArtistsRepositoryProvider)
        .fetchAll();
    await _saveCache(favorites);
    unawaited(_upgradeArtworks(favorites));
    return favorites;
  }

  /// このセッションで画像の置き換えを試したお気に入り。
  /// 見つからなかったものを再取得（接続状態の変化など）のたびに問い合わせないため。
  final _artworkUpgradeAttempted = <String>{};

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

  Future<FavoriteArtist> add({
    required String name,
    int? itunesArtistId,
    String? artworkUrl,
  }) async {
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
    await ref.read(favoriteArtistsRepositoryProvider).remove(id);
    final next = [
      for (final f in state.asData?.value ?? const <FavoriteArtist>[])
        if (f.id != id) f,
    ];
    state = AsyncData(next);
    await _saveCache(next);
  }

  Future<void> _saveCache(List<FavoriteArtist> favorites) async {
    final userId = _userId;
    if (userId == null) return;
    await _cache.save(userId, [for (final f in favorites) f.toJson()]);
  }
}
