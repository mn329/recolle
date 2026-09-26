import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';

class ItunesArtist {
  const ItunesArtist({required this.id, required this.name, this.genre});

  final int id;
  final String name;
  final String? genre;
}

class ItunesSong {
  const ItunesSong({
    required this.id,
    required this.title,
    required this.artistName,
    this.artworkUrl,
  });

  final int id;
  final String title;
  final String artistName;
  final String? artworkUrl;
}

/// iTunes Search API（キー不要・無料）のクライアント。
///
/// Apple は目安として 1 分あたり約 20 リクエストに制限しているため、
/// 同じ URL の結果はメモリにキャッシュし、呼び出し側でも入力をデバウンスする。
class ItunesClient {
  ItunesClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const _timeout = Duration(seconds: 8);
  static const _maxCacheEntries = 100;
  static const _artworkSize = 400;

  final http.Client _http;

  /// Dart の Map リテラルは挿入順を保つので、先頭が最も古いエントリになる。
  final _cache = <Uri, List<Map<String, dynamic>>>{};

  Future<List<ItunesArtist>> searchArtists(String term, {int limit = 8}) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return const [];
    final results = await _search({
      'term': trimmed,
      'entity': 'musicArtist',
      'limit': '$limit',
    });
    final seen = <int>{};
    return [
      for (final r in results)
        if (r['artistId'] is int &&
            r['artistName'] is String &&
            seen.add(r['artistId'] as int))
          ItunesArtist(
            id: r['artistId'] as int,
            name: r['artistName'] as String,
            genre: r['primaryGenreName'] as String?,
          ),
    ];
  }

  /// [artistName] の曲から [term] に合うものを返す。曲名の重複（別アルバム収録など）は除く。
  Future<List<ItunesSong>> searchSongs({
    required String artistName,
    required String term,
    int limit = 6,
  }) async {
    final artist = artistName.trim();
    final query = term.trim();
    if (query.isEmpty) return const [];
    final results = await _search({
      'term': artist.isEmpty ? query : '$artist $query',
      'entity': 'song',
      'limit': '25',
    });
    final seenTitles = <String>{};
    final songs = <ItunesSong>[];
    for (final r in results) {
      final title = r['trackName'];
      final songArtist = r['artistName'];
      final id = r['trackId'];
      if (title is! String || songArtist is! String || id is! int) continue;
      if (artist.isNotEmpty && !artistMatches(songArtist, artist)) continue;
      if (!seenTitles.add(normalizeArtistName(title))) continue;
      songs.add(
        ItunesSong(
          id: id,
          title: title,
          artistName: songArtist,
          artworkUrl: _resizeArtwork(r['artworkUrl100'] as String?),
        ),
      );
      if (songs.length >= limit) break;
    }
    return songs;
  }

  /// アーティスト画像は API にないので、代表アルバムのジャケットで代用する。
  Future<String?> findArtistArtwork(String artistName) async {
    final artist = artistName.trim();
    if (artist.isEmpty) return null;
    final results = await _search({
      'term': artist,
      'entity': 'album',
      'attribute': 'artistTerm',
      'limit': '5',
    });
    for (final r in results) {
      final name = r['artistName'];
      if (name is String && artistMatches(name, artist)) {
        return _resizeArtwork(r['artworkUrl100'] as String?);
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _search(Map<String, String> params) async {
    final uri = Uri.https('itunes.apple.com', '/search', {
      ...params,
      'media': 'music',
      'country': 'JP',
      'lang': 'ja_jp',
    });

    final cached = _cache.remove(uri);
    if (cached != null) {
      _cache[uri] = cached;
      return cached;
    }

    final http.Response res;
    try {
      res = await _http.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const UserFacingException('曲情報の取得がタイムアウトしました。');
    }
    if (res.statusCode == 403 || res.statusCode == 429) {
      throw const UserFacingException('曲情報の検索が混み合っています。少し待ってからお試しください。');
    }
    if (res.statusCode != 200) {
      throw UserFacingException('曲情報を取得できませんでした (${res.statusCode})。');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final results = decoded is Map && decoded['results'] is List
        ? [
            for (final r in decoded['results'] as List)
              if (r is Map) Map<String, dynamic>.from(r),
          ]
        : <Map<String, dynamic>>[];

    _cache[uri] = results;
    if (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    return results;
  }

  static String? _resizeArtwork(String? url) {
    if (url == null || !url.startsWith('https://')) return null;
    return url.replaceFirst(
      RegExp(r'/\d+x\d+bb\.'),
      '/${_artworkSize}x${_artworkSize}bb.',
    );
  }
}
