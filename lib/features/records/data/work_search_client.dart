import 'package:flutter/foundation.dart';
import 'package:recolle/core/network/edge_function.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 映画・本の題名候補。
@immutable
class WorkSuggestion {
  const WorkSuggestion({
    required this.title,
    this.creator,
    this.year,
    this.artworkUrl,
    this.description,
  });

  /// 形式が壊れていれば null。サーバーでも整えているが、アプリ側でも信用しない。
  static WorkSuggestion? tryParse(Object? json) {
    if (json is! Map) return null;
    final title = _text(json['title']);
    if (title == null) return null;
    final year = json['year'];
    final artwork = Uri.tryParse(_text(json['artworkUrl']) ?? '');
    return WorkSuggestion(
      title: title,
      creator: _text(json['creator']),
      year: year is int && year > 0 ? year : null,
      artworkUrl: artwork != null && artwork.isScheme('https')
          ? artwork.toString()
          : null,
      description: _text(json['description']),
    );
  }

  final String title;

  /// 映画は監督、本は著者。
  final String? creator;
  final int? year;
  final String? artworkUrl;

  /// 同名の作品を見分けるための短い説明（映画の原題など）。
  final String? description;

  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}

/// Edge Function `work-search` 経由で映画（TMDB）・本（楽天ブックス）の題名を探す。
///
/// 入力途中の検索が続くので、同じ検索の結果はメモリにキャッシュし、同時に走った同じ検索は
/// 1 回の問い合わせにまとめる。呼び出し側でも入力をデバウンスする。
class WorkSearchClient {
  WorkSearchClient(this._functions);

  static const _maxCacheEntries = 100;

  final FunctionsClient _functions;

  /// Dart の Map リテラルは挿入順を保つので、先頭が最も古いエントリになる。
  final _cache = <String, List<WorkSuggestion>>{};
  final _inFlight = <String, Future<List<WorkSuggestion>>>{};

  Future<List<WorkSuggestion>> searchBooks(String term) =>
      _search('book', term);

  Future<List<WorkSuggestion>> searchMovies(String term) =>
      _search('movie', term);

  Future<List<WorkSuggestion>> _search(String type, String term) async {
    final query = term.trim();
    if (query.isEmpty) return const [];
    final key = '$type|$query';

    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final request = _fetch(type, query);
    _inFlight[key] = request;
    try {
      final works = await request;
      _cache[key] = works;
      if (_cache.length > _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
      return works;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<List<WorkSuggestion>> _fetch(String type, String query) async {
    final data = await invokeEdgeFunction(
      _functions,
      'work-search',
      body: {'type': type, 'query': query},
      messageForError: (code, status) =>
          messageForError(code, status, type: type),
      timeout: const Duration(seconds: 15),
    );
    if (data is! Map || data['works'] is! List) {
      throw const UserFacingException('候補の形式が想定外でした。');
    }
    return [for (final w in data['works'] as List) ?WorkSuggestion.tryParse(w)];
  }

  @visibleForTesting
  static String messageForError(
    Object? code,
    int status, {
    required String type,
  }) {
    final label = type == 'book' ? '本' : '映画';
    return switch (code) {
      'work_search_not_configured' => '$labelの検索は現在ご利用いただけません。',
      'work_search_rate_limited' => '$labelの検索が混み合っています。少し待ってからお試しください。',
      'work_search_timeout' => '$labelの情報の取得に時間がかかっています。少し待ってからお試しください。',
      _ => '$labelの情報を取得できませんでした ($status)。',
    };
  }
}
