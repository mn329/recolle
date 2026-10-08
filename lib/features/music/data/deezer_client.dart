import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';

/// Deezer API（キー不要・無料）のクライアント。アーティスト画像の取得だけに使う。
///
/// iTunes Search API にはアーティスト画像がないため、その補完として使う。
/// 制限は 5 秒あたり 50 リクエスト。超えると HTTP 200 のまま `error` を返す。
class DeezerClient {
  DeezerClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const _timeout = Duration(seconds: 8);

  final http.Client _http;

  /// [artistName] のアーティスト画像（500x500）。見つからなければ null。
  ///
  /// Deezer は日本語名で検索してもローマ字表記（例: サカナクション → Sakanaction）で
  /// 返すことがあるので、名前が一致しない場合でも日本語の検索語なら最上位の結果を採用する。
  Future<String?> findArtistImage(String artistName) async {
    final name = artistName.trim();
    if (name.isEmpty) return null;

    final uri = Uri.https('api.deezer.com', '/search/artist', {
      'q': name,
      'limit': '5',
    });
    final http.Response res;
    try {
      res = await _http.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const UserFacingException('アーティスト画像の取得がタイムアウトしました。');
    }
    if (res.statusCode != 200) {
      throw UserFacingException('アーティスト画像を取得できませんでした (${res.statusCode})。');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) return null;
    if (decoded['error'] is Map) {
      throw const UserFacingException('アーティスト画像の検索が混み合っています。');
    }
    final data = decoded['data'];
    if (data is! List) return null;

    final artists = [
      for (final r in data)
        if (r is Map && r['name'] is String)
          (name: r['name'] as String, picture: r['picture_big']),
    ];
    final target = normalizeArtistName(name);
    // 本人に画像がないときに別人の画像を拾わないよう、一致した時点で打ち切る
    final match =
        artists
            .where((a) => normalizeArtistName(a.name) == target)
            .firstOrNull ??
        (_nonLatin.hasMatch(name) ? artists.firstOrNull : null);
    return match == null ? null : _imageUrl(match.picture);
  }

  static final _nonLatin = RegExp(r'[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]');

  /// 画像未登録のアーティストはハッシュ部分が空のプレースホルダー
  /// （`/images/artist//500x500-...`）になるので除く。
  static String? _imageUrl(Object? raw) {
    if (raw is! String || !raw.startsWith('https://')) return null;
    if (raw.contains('/images/artist//')) return null;
    return raw;
  }
}
