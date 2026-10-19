import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/records/data/records_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FavoriteArtistsRepository {
  FavoriteArtistsRepository(this._client);

  static const _table = 'favorite_artists';
  static const maxNameLength = 100;
  static const _uploadTimeout = Duration(seconds: 60);

  final SupabaseClient _client;

  Future<List<FavoriteArtist>> fetchAll() async {
    final rows = await _client
        .from(_table)
        .select()
        .order('created_at', ascending: true);
    return [for (final row in rows) FavoriteArtist.fromJson(row)];
  }

  Future<FavoriteArtist> add({
    required String name,
    int? itunesArtistId,
    String? artworkUrl,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const UserFacingException('アーティスト名を入力してください。');
    }
    if (trimmed.length > maxNameLength) {
      throw const UserFacingException('アーティスト名は$maxNameLength文字までです。');
    }
    try {
      final row = await _client
          .from(_table)
          .insert({
            'name': trimmed,
            'itunes_artist_id': itunesArtistId,
            'artwork_url': artworkUrl,
          })
          .select()
          .single();
      return FavoriteArtist.fromJson(row);
    } on PostgrestException catch (e) {
      // unique_violation
      if (e.code == '23505') {
        throw UserFacingException('「$trimmed」はすでにお気に入りです。');
      }
      rethrow;
    }
  }

  Future<void> updateArtwork(String id, String artworkUrl) async {
    await _client.from(_table).update({'artwork_url': artworkUrl}).eq('id', id);
  }

  /// 選んだ画像を、自分のフォルダに上げて、その URL を返す。
  ///
  /// チケット画像と同じバケットを使う。アカウント削除は `<userId>/` 直下のファイルだけを消すので、
  /// サブフォルダは作らず、ファイル名に `artist_` を付けて区別する。
  /// 置き換えのたびに別のファイル名にして、端末に残った古い画像の表示キャッシュと混ざらないようにする。
  Future<String> uploadCustomImage({
    required String userId,
    required String favoriteId,
    required File file,
  }) async {
    final extension = p.extension(file.path).toLowerCase();
    final storagePath =
        '$userId/artist_${favoriteId}_${DateTime.now().microsecondsSinceEpoch}'
        '${extension.isEmpty ? '.jpg' : extension}';
    final storage = _client.storage.from(RecordsRepository.bucket);
    await storage
        .upload(storagePath, file)
        .timeout(
          _uploadTimeout,
          onTimeout: () => throw const UserFacingException(
            '画像のアップロードがタイムアウトしました。電波の良い場所でもう一度お試しください。',
          ),
        );
    return storage.getPublicUrl(storagePath);
  }

  /// 独自画像を [imageUrl] にする。null なら外す（自動取得の写真に戻る）。
  Future<void> setCustomImage(String id, String? imageUrl) async {
    await _client
        .from(_table)
        .update({'custom_image_url': imageUrl})
        .eq('id', id);
  }

  /// [uploadCustomImage] で上げた画像を消す。このバケットの URL でないものは無視する。
  Future<void> deleteCustomImages(List<String> urls) async {
    final paths = [
      for (final url in urls) ?RecordsRepository.ticketImageStoragePath(url),
    ];
    if (paths.isEmpty) return;
    await _client.storage.from(RecordsRepository.bucket).remove(paths);
  }

  Future<void> remove(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }
}
