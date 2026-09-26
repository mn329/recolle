import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:recolle/core/utils/user_facing_exception.dart';

/// 映画・本の題名候補。
class WorkSuggestion {
  const WorkSuggestion({
    required this.title,
    this.creator,
    this.year,
    this.artworkUrl,
    this.description,
  });

  final String title;

  /// 映画は監督、本は著者。
  final String? creator;
  final int? year;
  final String? artworkUrl;

  /// 同名の作品を見分けるための短い説明（例: 「日本のアニメーション映画 (2016)」）。
  final String? description;
}

/// 映画・本の題名を探すクライアント。どちらもキー不要の公開 API を使う。
///
/// - 映画: Wikidata。iTunes Search API の映画検索は結果を返さなくなったため。
/// - 本: iTunes Search API の電子書籍。Google Books はキーなしの共有枠が 0 件になっている。
///
/// どちらも呼び出し回数の目安があるので、同じ URL の結果はメモリにキャッシュし、
/// 呼び出し側でも入力をデバウンスする。
class WorkSearchClient {
  WorkSearchClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  static const _timeout = Duration(seconds: 8);
  static const _maxCacheEntries = 100;
  static const _artworkSize = 200;

  /// Wikidata は連絡先の分かる User-Agent を求めている。
  static const _headers = {
    'User-Agent': 'recolle/1.0 (https://github.com/mn329/recolle)',
  };

  /// 説明文が「映画」を指すもの。
  static final _filmDescription = RegExp(
    r'映画|film|movie',
    caseSensitive: false,
  );

  /// 映画に関連する別物（曲・サウンドトラック・一覧など）。「『〇〇シリーズ』の第1作目」は映画なので、
  /// シリーズそのものを指す「映画シリーズ」だけを除く。
  static final _notAFilm = RegExp(
    r'サウンドトラック|soundtrack|主題歌|楽曲|instrumental|song|album|single|'
    r'曖昧さ回避|disambiguation|一覧|映画シリーズ|film series|media franchise',
    caseSensitive: false,
  );

  final http.Client _http;

  /// Dart の Map リテラルは挿入順を保つので、先頭が最も古いエントリになる。
  final _cache = <Uri, Object?>{};

  Future<List<WorkSuggestion>> searchBooks(String term, {int limit = 5}) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return const [];
    final decoded = await _getJson(
      Uri.https('itunes.apple.com', '/search', {
        'term': trimmed,
        'media': 'ebook',
        'limit': '$limit',
        'country': 'JP',
        'lang': 'ja_jp',
      }),
      label: '本',
    );
    final results = decoded is Map ? decoded['results'] : null;
    if (results is! List) return const [];
    // limit より多く返ることがある
    return [
      for (final r in results)
        if (r is Map && r['trackName'] is String)
          WorkSuggestion(
            title: r['trackName'] as String,
            creator: r['artistName'] as String?,
            year: _yearOf(r['releaseDate']),
            artworkUrl: _resizeArtwork(r['artworkUrl100']),
          ),
    ].take(limit).toList();
  }

  Future<List<WorkSuggestion>> searchMovies(
    String term, {
    int limit = 5,
  }) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return const [];
    // 映画以外（曲・ドラマ・人物など）も混ざるので多めに引いて絞る
    final searched = await _wikidata({
      'action': 'wbsearchentities',
      'search': trimmed,
      'language': 'ja',
      'uselang': 'ja',
      'type': 'item',
      'limit': '20',
    });
    final hits = searched is Map ? searched['search'] : null;
    if (hits is! List) return const [];
    final films = [
      for (final h in hits)
        if (h is Map &&
            h['id'] is String &&
            h['label'] is String &&
            h['description'] is String &&
            _filmDescription.hasMatch(h['description'] as String) &&
            !_notAFilm.hasMatch(h['description'] as String))
          (
            id: h['id'] as String,
            title: _stripDisambiguation(h['label'] as String),
            description: h['description'] as String,
          ),
    ].take(limit).toList();
    if (films.isEmpty) return const [];

    // 監督と公開年は補足なので、取れなくても題名の候補は出す
    final details = <String, ({List<String> directorIds, int? year})>{};
    final directorNames = <String, String>{};
    try {
      final claims = await _wikidata({
        'action': 'wbgetentities',
        'ids': films.map((f) => f.id).join('|'),
        'props': 'claims',
      });
      final entities = claims is Map ? claims['entities'] : null;
      if (entities is Map) {
        for (final f in films) {
          final c = entities[f.id] is Map ? entities[f.id]['claims'] : null;
          if (c is! Map) continue;
          details[f.id] = (
            directorIds: _entityIds(c['P57']),
            year: _earliestYear(c['P577']),
          );
        }
      }
      final directorIds = {
        for (final d in details.values) ...d.directorIds.take(2),
      };
      if (directorIds.isNotEmpty) {
        final labels = await _wikidata({
          'action': 'wbgetentities',
          'ids': directorIds.join('|'),
          'props': 'labels',
          'languages': 'ja|en',
        });
        final people = labels is Map ? labels['entities'] : null;
        if (people is Map) {
          for (final id in directorIds) {
            final l = people[id] is Map ? people[id]['labels'] : null;
            if (l is! Map) continue;
            final name = (l['ja'] ?? l['en']);
            if (name is Map && name['value'] is String) {
              directorNames[id] = name['value'] as String;
            }
          }
        }
      }
    } on UserFacingException {
      // 題名だけで候補を出す
    }

    return [
      for (final f in films)
        WorkSuggestion(
          title: f.title,
          description: f.description,
          year: details[f.id]?.year,
          creator: _joinOrNull([
            for (final id in details[f.id]?.directorIds.take(2) ?? <String>[])
              ?directorNames[id],
          ]),
        ),
    ];
  }

  Future<Object?> _wikidata(Map<String, String> params) => _getJson(
    Uri.https('www.wikidata.org', '/w/api.php', {...params, 'format': 'json'}),
    label: '映画',
  );

  Future<Object?> _getJson(Uri uri, {required String label}) async {
    if (_cache.containsKey(uri)) {
      final cached = _cache.remove(uri);
      _cache[uri] = cached;
      return cached;
    }

    final http.Response res;
    try {
      res = await _http.get(uri, headers: _headers).timeout(_timeout);
    } on TimeoutException {
      throw UserFacingException('$labelの情報の取得がタイムアウトしました。');
    }
    if (res.statusCode == 403 || res.statusCode == 429) {
      throw UserFacingException('$labelの検索が混み合っています。少し待ってからお試しください。');
    }
    if (res.statusCode != 200) {
      throw UserFacingException('$labelの情報を取得できませんでした (${res.statusCode})。');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw UserFacingException('$labelの情報を読み取れませんでした。');
    }
    _cache[uri] = decoded;
    if (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    return decoded;
  }

  static List<String> _entityIds(Object? statements) => [
    if (statements is List)
      for (final s in statements)
        if (s is Map &&
            s['mainsnak'] is Map &&
            s['mainsnak']['datavalue'] is Map &&
            s['mainsnak']['datavalue']['value'] is Map &&
            s['mainsnak']['datavalue']['value']['id'] is String)
          s['mainsnak']['datavalue']['value']['id'] as String,
  ];

  /// 公開日は国ごとに複数あるので、最も早い年を使う。
  static int? _earliestYear(Object? statements) {
    if (statements is! List) return null;
    int? earliest;
    for (final s in statements) {
      if (s is! Map || s['mainsnak'] is! Map) continue;
      final value = s['mainsnak']['datavalue'];
      final time = value is Map && value['value'] is Map
          ? value['value']['time']
          : null;
      // 形式は "+2016-08-26T00:00:00Z"
      final year = time is String
          ? int.tryParse(time.replaceFirst('+', '').split('-').first)
          : null;
      if (year != null && (earliest == null || year < earliest)) {
        earliest = year;
      }
    }
    return earliest;
  }

  /// 同名の別作品と区別するための括弧（例: 「スラムダンク (1994年の映画)」）を外す。
  static String _stripDisambiguation(String label) {
    final stripped = label.replaceFirst(_disambiguationSuffix, '').trim();
    return stripped.isEmpty ? label : stripped;
  }

  static final _disambiguationSuffix = RegExp(
    r'\s*[(（][^()（）]*(映画|film)[^()（）]*[)）]$',
    caseSensitive: false,
  );

  static int? _yearOf(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.year : null;

  static String? _resizeArtwork(Object? raw) {
    if (raw is! String || !raw.startsWith('https://')) return null;
    return raw.replaceFirst(
      RegExp(r'\d+x\d+bb'),
      '${_artworkSize}x${_artworkSize}bb',
    );
  }

  static String? _joinOrNull(List<String> names) =>
      names.isEmpty ? null : names.join('・');
}
