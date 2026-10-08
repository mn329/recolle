import 'package:recolle/core/network/edge_function.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Edge Function `song-title-ja` 経由で、ローマ字・英字の曲名の日本語表記の候補を Gemini に聞く。
///
/// 返るのは候補だけで、曲名を保証しない。使う側が iTunes で、そのアーティストの曲として
/// 実在するかを確かめてから使う。サーバーは同じ曲をキャッシュし、呼び出し回数にも上限がある。
class SongTitleClient {
  SongTitleClient(this._functions);

  final FunctionsClient _functions;

  /// 一度に聞ける曲数。サーバー側の上限と揃える。
  static const maxTitles = 10;

  /// 「曲名 → 日本語表記の候補」。見つからなかった曲は含めない。
  Future<Map<String, String>> suggest(
    String artistName,
    List<String> titles,
  ) async {
    final asked = titles.take(maxTitles).toList();
    if (artistName.trim().isEmpty || asked.isEmpty) return const {};
    final data = await invokeEdgeFunction(
      _functions,
      'song-title-ja',
      body: {'artist': artistName.trim(), 'titles': asked},
      messageForError: messageForError,
      timeout: const Duration(seconds: 20),
    );
    if (data is! Map || data['titles'] is! Map) {
      throw const UserFacingException('曲名の形式が想定外でした。');
    }
    final map = data['titles'] as Map;
    return {
      for (final title in asked)
        if (map[title] case final String japanese when japanese.isNotEmpty)
          title: japanese,
    };
  }

  static String messageForError(Object? code, int status) => switch (code) {
    'song_title_not_configured' => '曲名の変換は現在ご利用いただけません。',
    'song_title_daily_limit' => '今日の曲名の変換の回数の上限に達しました。',
    'song_title_global_limit' => '曲名の変換が混み合っています。',
    'song_title_rate_limited' => '曲名の変換が混み合っています。',
    'song_title_timeout' => '曲名の変換に時間がかかっています。',
    _ => '曲名を変換できませんでした ($status)。',
  };
}
