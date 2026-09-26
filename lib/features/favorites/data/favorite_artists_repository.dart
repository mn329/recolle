import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FavoriteArtistsRepository {
  FavoriteArtistsRepository(this._client);

  static const _table = 'favorite_artists';
  static const maxNameLength = 100;

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

  Future<void> remove(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }
}
