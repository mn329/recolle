import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:recolle/features/music/data/romaji_to_hiragana.dart';

class ItunesArtist {
  const ItunesArtist({
    required this.id,
    required this.name,
    this.genre,
    this.appleMusicUrl,
  });

  /// `artistId` と `artistName` が揃っていない結果は null。
  static ItunesArtist? tryParse(Map<String, dynamic> r) {
    final id = r['artistId'];
    final name = r['artistName'];
    if (id is! int || name is! String) return null;
    return ItunesArtist(
      id: id,
      name: name,
      genre: r['primaryGenreName'] as String?,
      appleMusicUrl: _httpsUri(r['artistLinkUrl']),
    );
  }

  final int id;
  final String name;
  final String? genre;
  final Uri? appleMusicUrl;

  ItunesArtist withName(String name) => ItunesArtist(
    id: id,
    name: name,
    genre: genre,
    appleMusicUrl: appleMusicUrl,
  );
}

class ItunesSong {
  const ItunesSong({
    required this.id,
    required this.title,
    required this.artistName,
    this.artistId,
    this.albumName,
    this.artworkUrl,
    this.releaseDate,
    this.duration,
    this.appleMusicUrl,
    this.previewUrl,
  });

  /// `trackId`・`trackName`・`artistName` が揃っていない結果は null。
  static ItunesSong? tryParse(Map<String, dynamic> r) {
    final id = r['trackId'];
    final title = r['trackName'];
    final artistName = r['artistName'];
    if (id is! int || title is! String || artistName is! String) return null;
    final millis = r['trackTimeMillis'];
    final released = r['releaseDate'];
    return ItunesSong(
      id: id,
      title: title,
      artistName: artistName,
      artistId: r['artistId'] as int?,
      albumName: r['collectionName'] as String?,
      artworkUrl: ItunesClient._resizeArtwork(r['artworkUrl100'] as String?),
      releaseDate: released is String ? DateTime.tryParse(released) : null,
      duration: millis is int ? Duration(milliseconds: millis) : null,
      appleMusicUrl: _httpsUri(r['trackViewUrl']),
      previewUrl: _httpsUri(r['previewUrl']),
    );
  }

  final int id;
  final String title;
  final String artistName;
  final int? artistId;
  final String? albumName;
  final String? artworkUrl;
  final DateTime? releaseDate;
  final Duration? duration;
  final Uri? appleMusicUrl;

  /// 約 30 秒の試聴音源（AAC）。
  final Uri? previewUrl;
}

Uri? _httpsUri(Object? raw) {
  if (raw is! String) return null;
  final uri = Uri.tryParse(raw);
  return uri != null && uri.scheme == 'https' ? uri : null;
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
  final _inFlight = <Uri, Future<List<Map<String, dynamic>>>>{};

  Future<List<ItunesArtist>> searchArtists(String term, {int limit = 8}) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return const [];
    // 並行して引く。_japaneseArtistNames は失敗しても例外を投げない
    final japaneseNamesFuture = _containsJapanese(trimmed)
        ? _japaneseArtistNames(trimmed)
        : Future.value(const <int, String>{});
    final results = await _search({
      'term': trimmed,
      'entity': 'musicArtist',
      'limit': '$limit',
    });
    final japaneseNames = await japaneseNamesFuture;
    final seen = <int>{};
    return [
      for (final r in results)
        if (ItunesArtist.tryParse(r) case final artist?
            when seen.add(artist.id))
          switch (japaneseNames[artist.id]) {
            final ja? when !_containsJapanese(artist.name) => artist.withName(
              ja,
            ),
            _ => artist,
          },
    ];
  }

  /// 日本語で探した人には日本語名で見せたいので、曲の検索から artistId ごとの日本語名を拾う。
  /// 補助的な情報なので、失敗しても英字名のまま出せるよう空で返す。
  Future<Map<int, String>> _japaneseArtistNames(String term) async {
    try {
      final songs = await _search({
        'term': term,
        'entity': 'song',
        'attribute': 'artistTerm',
        'limit': '50',
      });
      // コラボ曲は "A & B" のような表記になるので、ID ごとに最も多い表記を採る
      final counts = <int, Map<String, int>>{};
      for (final r in songs) {
        final id = r['artistId'];
        final name = r['artistName'];
        if (id is int && name is String && _containsJapanese(name)) {
          final byName = counts.putIfAbsent(id, () => {});
          byName[name] = (byName[name] ?? 0) + 1;
        }
      }
      return {
        for (final MapEntry(key: id, value: byName) in counts.entries)
          id: byName.entries.reduce((a, b) => b.value > a.value ? b : a).key,
      };
    } catch (e) {
      debugPrint('Japanese artist name lookup failed for $term: $e');
      return const {};
    }
  }

  /// 名前に一致するアーティスト。[artistId] が分かっていればそれで引く。
  Future<ItunesArtist?> findArtist(String artistName, {int? artistId}) async {
    if (artistId != null) {
      final results = await _artistLookup(artistId);
      final found = results
          .where((r) => r['wrapperType'] == 'artist')
          .map(ItunesArtist.tryParse)
          .nonNulls
          .firstOrNull;
      if (found != null) return found;
    }
    final candidates = await searchArtists(artistName, limit: 5);
    final target = normalizeArtistName(artistName);
    return candidates
            .where((a) => normalizeArtistName(a.name) == target)
            .firstOrNull ??
        candidates.where((a) => artistMatches(a.name, artistName)).firstOrNull;
  }

  /// アーティストの人気曲（iTunes の lookup は人気順で返す）。同名曲は 1 つにまとめる。
  /// [limit] は [_artistLookupSongs] までで、同名曲をまとめた分だけ少なくなることがある。
  Future<List<ItunesSong>> topSongs(int artistId, {int limit = 10}) async {
    final results = await _artistLookup(artistId);
    final seenTitles = <String>{};
    return results
        .map(ItunesSong.tryParse)
        .nonNulls
        .where((s) => seenTitles.add(normalizeArtistName(_baseTitle(s.title))))
        .take(limit)
        .toList();
  }

  static const _artistLookupSongs = 20;

  /// 先頭にアーティスト自身、続いて人気順の曲が入る。findArtist と topSongs で URL をそろえ、
  /// アーティスト詳細を開いたときの 2 つの問い合わせを 1 回の通信で済ませる。
  Future<List<Map<String, dynamic>>> _artistLookup(int artistId) => _get(
    '/lookup',
    {'id': '$artistId', 'entity': 'song', 'limit': '$_artistLookupSongs'},
  );

  /// 記録のセトリの曲名から iTunes の曲を探す。見つからなければ null。
  Future<ItunesSong?> findSong({
    required String artistName,
    required String title,
  }) async {
    final songs = await searchSongs(
      artistName: artistName,
      term: title,
      limit: 10,
    );
    final target = normalizeArtistName(title);
    return songs
            .where((s) => normalizeArtistName(s.title) == target)
            .firstOrNull ??
        songs
            .where((s) => normalizeArtistName(_baseTitle(s.title)) == target)
            .firstOrNull ??
        songs.firstOrNull;
  }

  /// セトリの曲名ごとに Apple Music の曲 ID（iTunes の trackId と同じ）を探す。
  ///
  /// 返り値は「曲名 → trackId」で、見つからなかった曲は含めない。プレイリストに別の曲が
  /// 入らないよう、曲名が一致したもの（付記の違いは許す）だけを使う。
  /// 1. アーティストの曲一覧（1 リクエスト、セトリの日本語化と共有のキャッシュ）から探す
  /// 2. 残りはレート制限を考えて [maxIndividualLookups] 曲まで 1 曲ずつ検索する
  Future<Map<String, int>> findSongIds({
    required String artistName,
    required List<String> titles,
    int maxIndividualLookups = 10,
  }) async {
    final artist = artistName.trim();
    final pending = {
      for (final t in titles)
        if (t.trim().isNotEmpty) t,
    };
    if (artist.isEmpty || pending.isEmpty) return {};

    int? matchIn(Iterable<Map<String, dynamic>> results, String title) {
      final target = normalizeArtistName(title);
      int? loose;
      for (final r in results) {
        final id = r['trackId'];
        final name = r['trackName'];
        final songArtist = r['artistName'];
        if (id is! int ||
            name is! String ||
            songArtist is! String ||
            !artistMatches(songArtist, artist)) {
          continue;
        }
        if (normalizeArtistName(name) == target) return id;
        if (loose == null && normalizeArtistName(_baseTitle(name)) == target) {
          loose = id;
        }
      }
      return loose;
    }

    final catalog = await _songCatalog(artist, 'JP');
    final result = <String, int>{};
    for (final title in pending) {
      final id = matchIn(catalog, title);
      if (id != null) result[title] = id;
    }

    final unresolved = pending
        .where((t) => !result.containsKey(t))
        .take(maxIndividualLookups)
        .toList();
    final found = await Future.wait([
      for (final title in unresolved)
        _search({
          'term': '$artist $title',
          'entity': 'song',
          'limit': '10',
        }).then((hits) => matchIn(hits, title)).catchError((Object e) {
          // 一部の曲の検索が失敗しても、見つかった曲だけでプレイリストは作れる
          debugPrint('Song id lookup failed for "$title": $e');
          return null;
        }, test: (e) => e is UserFacingException),
    ]);
    for (final (i, id) in found.indexed) {
      if (id != null) result[unresolved[i]] = id;
    }

    // まだ見つからない曲は、日本語表記で探す（Kaze to Machi → 風と町、Columbus → コロンブス）
    // すでに日本語の曲名は対象外（別の曲を入れないため）。英字の曲名だけを日本語表記で探す
    final stillUnresolved = unresolved
        .where((t) => !result.containsKey(t) && !_containsJapanese(t))
        .toList();
    final japaneseHits = await Future.wait([
      for (final title in stillUnresolved)
        _findJapaneseHit(artist, title, strict: true),
    ]);
    for (final (i, hit) in japaneseHits.indexed) {
      final id = hit?['trackId'];
      if (id is int) result[stillUnresolved[i]] = id;
    }
    return result;
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
    return results
        .map(ItunesSong.tryParse)
        .nonNulls
        .where((s) => artist.isEmpty || artistMatches(s.artistName, artist))
        .where((s) => seenTitles.add(normalizeArtistName(s.title)))
        .take(limit)
        .toList();
  }

  /// アーティスト画像は API にないので、代表アルバムのジャケットで代用する。
  /// `ArtistArtworkFinder` が、Deezer にアーティスト画像がないときの代用として使う。
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
  ///
  /// どのリクエストも待ち時間を足し合わせないよう同時に投げる。
  Future<Map<String, String>> localizeSongTitles({
    required String artistName,
    required List<String> titles,
    int maxIndividualLookups = 10,
  }) async {
    final artist = artistName.trim();
    final pending = {
      for (final t in titles)
        if (!_containsJapanese(t)) t,
    };
    if (artist.isEmpty || pending.isEmpty) return {};

    final [jpCatalog, usCatalog] = await Future.wait([
      _songCatalog(artist, 'JP'),
      _songCatalog(artist, 'US'),
    ]);

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
        .take(maxIndividualLookups)
        .toList();
    final found = await Future.wait([
      for (final title in unresolved) _findJapaneseTitle(artist, title),
    ]);
    for (final (i, japanese) in found.indexed) {
      if (japanese != null) result[unresolved[i]] = japanese;
    }
    return result;
  }

  /// セトリの日本語化に使うカタログを先に読んでおく。
  /// 公演の候補を選んでからの待ち時間を減らすためで、失敗しても何もしない。
  Future<void> prefetchSongCatalog(String artistName) async {
    final artist = artistName.trim();
    if (artist.isEmpty) return;
    try {
      await Future.wait([
        _songCatalog(artist, 'JP'),
        _songCatalog(artist, 'US'),
      ]);
    } catch (e) {
      debugPrint('Song catalog prefetch failed for $artist: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _songCatalog(
    String artist,
    String country,
  ) => _search({
    'term': artist,
    'entity': 'song',
    'attribute': 'artistTerm',
    'limit': '200',
  }, country: country);

  /// 日本ストアで [title] を検索し、日本語の曲名を返す。
  /// 日本語化は補助なので、レート制限などで失敗したら null にして元の表記を使ってもらう。
  Future<String?> _findJapaneseTitle(String artist, String title) async {
    final hit = await _findJapaneseHit(artist, title);
    return hit == null ? null : _baseTitle(hit['trackName'] as String);
  }

  /// 日本ストアで [title] を探し、日本語の曲名の検索結果（曲名・trackId を含む）を返す。
  ///
  /// 1. 「アーティスト 曲名」で検索する（英語の曲名の日本語表記はこれで見つかる。Columbus → コロンブス）
  /// 2. 見つからなければ、ローマ字をひらがなにして探す（Kaze to Machi → かぜとまち → 風と町）
  ///
  /// [strict] のときは、1 でそのアーティストの先頭の結果が日本語の曲名のときだけ採用する。
  /// プレイリストに別の曲が入らないようにするため。
  Future<Map<String, dynamic>?> _findJapaneseHit(
    String artist,
    String title, {
    bool strict = false,
  }) async {
    final List<Map<String, dynamic>> hits;
    try {
      hits = await _search({
        'term': '$artist $title',
        'entity': 'song',
        'limit': '5',
      });
    } on UserFacingException catch (e) {
      debugPrint('Song title lookup failed for "$title": ${e.userMessage}');
      return null;
    }
    for (final r in hits) {
      final name = r['trackName'];
      final songArtist = r['artistName'];
      if (name is! String ||
          songArtist is! String ||
          !artistMatches(songArtist, artist)) {
        continue;
      }
      if (_containsJapanese(name)) return r;
      if (strict) break;
    }
    return (await _searchByReading(artist, title)).firstOrNull;
  }

  /// 曲名のローマ字をひらがなにして、日本ストアで検索する（"Kaze to Machi" → "かぜとまち" → 「風と町」）。
  ///
  /// iTunes の検索は、ひらがなの読みで漢字の曲名を引ける。ローマ字から漢字は引けないので、
  /// 日本語の曲のローマ字表記は、これで探す。ひらがなにできない曲名（英語の曲名）は何もしない。
  /// 同じ曲名の別のアーティストの曲も出るので、アーティストが合うものだけを返す。
  Future<List<Map<String, dynamic>>> _searchByReading(
    String artist,
    String title,
  ) async {
    // 助詞（wa・e・o）があるときは「は・へ・を」の読みを先に、次にそのままの読みを試す
    for (final reading in romajiReadings(title)) {
      final List<Map<String, dynamic>> hits;
      try {
        hits = await _search({
          'term': reading,
          'entity': 'song',
          'limit': '25',
        });
      } on UserFacingException catch (e) {
        debugPrint('Reading lookup failed for "$title": ${e.userMessage}');
        return const [];
      }
      final matched = [
        for (final r in hits)
          if (r['trackName'] is String &&
              r['artistName'] is String &&
              artistMatches(r['artistName'] as String, artist) &&
              _containsJapanese(r['trackName'] as String))
            r,
      ];
      if (matched.isNotEmpty) return matched;
    }
    return const [];
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
  }) {
    return _get('/search', {...params, 'media': 'music'}, country: country);
  }

  Future<List<Map<String, dynamic>>> _get(
    String path,
    Map<String, String> params, {
    String country = 'JP',
  }) async {
    final uri = Uri.https('itunes.apple.com', path, {
      ...params,
      'country': country,
      if (country == 'JP') 'lang': 'ja_jp',
    });

    final cached = _cache.remove(uri);
    if (cached != null) {
      _cache[uri] = cached;
      return cached;
    }
    // 先読み中の同じ検索に相乗りし、レート制限の枠を二重に使わない
    final inFlight = _inFlight[uri];
    if (inFlight != null) return inFlight;

    final request = _fetch(uri);
    _inFlight[uri] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(uri);
    }
  }

  Future<List<Map<String, dynamic>>> _fetch(Uri uri) async {
    final http.Response res;
    try {
      res = await _http.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const UserFacingException('曲情報の取得がタイムアウトしました。');
    } catch (e) {
      // 接続できない（SocketException / ClientException）。呼び出し側は UserFacingException だけを受けるので変換する
      debugPrint('iTunes request failed: $e');
      throw UserFacingException(toUserFriendlyMessage(e));
    }
    if (res.statusCode == 403 || res.statusCode == 429) {
      throw const UserFacingException('曲情報の検索が混み合っています。少し待ってからお試しください。');
    }
    if (res.statusCode != 200) {
      throw UserFacingException('曲情報を取得できませんでした (${res.statusCode})。');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      // 公衆 Wi-Fi のログイン画面などが 200 で HTML を返すことがある
      throw const UserFacingException('曲情報を読み取れませんでした。ネットワークの接続を確認してください。');
    }
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
