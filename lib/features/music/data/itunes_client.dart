import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// setlist.fm の曲名はローマ字（例: "Gekijyo"）で登録されがちなので、日本語表記を探す。
  ///
  /// 返り値は「元の曲名 → 日本語表記」。見つからなかった曲は含めない。
  /// 1. 米国ストア（ローマ字名）と日本ストアの同じ trackId を突き合わせる（2 リクエスト）
  /// 2. 残りは日本ストアで 1 曲ずつ検索する。レート制限を考えて [maxIndividualLookups] 曲まで
  Future<Map<String, String>> localizeSongTitles({
    required String artistName,
    required List<String> titles,
    int maxIndividualLookups = 6,
  }) async {
    final artist = artistName.trim();
    final pending = {
      for (final t in titles)
        if (!_containsJapanese(t)) t,
    };
    if (artist.isEmpty || pending.isEmpty) return {};

    Future<List<Map<String, dynamic>>> catalog(String country) => _search({
      'term': artist,
      'entity': 'song',
      'attribute': 'artistTerm',
      'limit': '200',
    }, country: country);

    final jpCatalog = await catalog('JP');
    final usCatalog = await catalog('US');

    final japaneseNameById = <int, String>{
      for (final r in jpCatalog)
        if (r['trackId'] is int &&
            r['trackName'] is String &&
            r['artistName'] is String &&
            artistMatches(r['artistName'] as String, artist) &&
            _containsJapanese(r['trackName'] as String))
          r['trackId'] as int: _baseTitle(r['trackName'] as String),
    };
    final idsByRomanName = <String, List<int>>{};
    for (final r in usCatalog) {
      final id = r['trackId'];
      final name = r['trackName'];
      if (id is int && name is String) {
        idsByRomanName.putIfAbsent(normalizeArtistName(name), () => []).add(id);
      }
    }

    final result = <String, String>{};
    for (final title in pending) {
      final ids = idsByRomanName[normalizeArtistName(title)] ?? const [];
      final japanese = ids
          .map((id) => japaneseNameById[id])
          .nonNulls
          .firstOrNull;
      if (japanese != null) result[title] = japanese;
    }

    // "UNDEAD" のように英字が正式名の曲は、日本ストアにも同名であるので検索しない
    final officialNames = {
      for (final r in jpCatalog)
        if (r['trackName'] is String)
          normalizeArtistName(r['trackName'] as String),
    };
    final unresolved = pending
        .where(
          (t) =>
              !result.containsKey(t) &&
              !officialNames.contains(normalizeArtistName(t)),
        )
        .take(maxIndividualLookups);
    for (final title in unresolved) {
      final List<Map<String, dynamic>> hits;
      try {
        hits = await _search({
          'term': '$artist $title',
          'entity': 'song',
          'limit': '5',
        });
      } on UserFacingException catch (e) {
        // レート制限などで続けても失敗するだけなので、ここまでの結果で打ち切る
        debugPrint('Song title lookup stopped at "$title": ${e.userMessage}');
        break;
      }
      for (final r in hits) {
        final name = r['trackName'];
        final songArtist = r['artistName'];
        if (name is String &&
            songArtist is String &&
            artistMatches(songArtist, artist) &&
            _containsJapanese(name)) {
          result[title] = _baseTitle(name);
          break;
        }
      }
    }
    return result;
  }

  static final _japaneseChars = RegExp(r'[\u3040-\u30ff\u3400-\u9fff]');

  static bool _containsJapanese(String s) => _japaneseChars.hasMatch(s);

  /// 「祝福 - from CrosSing」「風と町(NHK…)」のような付記を落とす。
  static String _baseTitle(String name) {
    final stripped = name
        .replaceFirst(RegExp(r'\s+-\s+.*$'), '')
        .replaceFirst(RegExp(r'\s*[(（\[［].*$'), '')
        .trim();
    return stripped.isEmpty ? name : stripped;
  }

  Future<List<Map<String, dynamic>>> _search(
    Map<String, String> params, {
    String country = 'JP',
  }) async {
    final uri = Uri.https('itunes.apple.com', '/search', {
      ...params,
      'media': 'music',
      'country': country,
      if (country == 'JP') 'lang': 'ja_jp',
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
