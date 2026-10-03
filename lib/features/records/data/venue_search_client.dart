import 'package:flutter/foundation.dart';
import 'package:recolle/core/network/edge_function.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 地図から引いた会場の候補。
@immutable
class VenueSuggestion {
  const VenueSuggestion({
    required this.placeId,
    required this.name,
    this.address,
  });

  /// 形式が壊れていれば null。サーバーでも整えているが、アプリ側でも信用しない。
  static VenueSuggestion? tryParse(Object? json) {
    if (json is! Map) return null;
    final placeId = _text(json['placeId']);
    final name = _text(json['name']);
    if (placeId == null || name == null) return null;
    return VenueSuggestion(
      placeId: placeId,
      name: name,
      address: _text(json['address']),
    );
  }

  /// Google Places の場所 ID。同じ会場かどうかの判定に使える。
  final String placeId;

  /// 会場名。表記は Places のものに揃う。
  final String name;

  /// 同名の会場を見分けるための住所（都道府県から）。
  final String? address;

  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}

/// Edge Function `venue-search` 経由で Google Places から会場名を探す。
///
/// 入力途中の検索が続くので、同じ検索の結果はメモリにキャッシュし、同時に走った同じ検索は
/// 1 回の問い合わせにまとめる。呼び出し側でも入力をデバウンスする。
class VenueSearchClient {
  VenueSearchClient(this._functions);

  /// これより短い入力では候補が絞れず、問い合わせが無駄になるので投げない。
  static const int minQueryLength = 2;

  static const _maxCacheEntries = 100;

  final FunctionsClient _functions;

  /// Dart の Map リテラルは挿入順を保つので、先頭が最も古いエントリになる。
  final _cache = <String, List<VenueSuggestion>>{};
  final _inFlight = <String, Future<List<VenueSuggestion>>>{};

  /// [term] に合う会場。短すぎる入力は問い合わせずに空で返す。
  ///
  /// [sessionToken] は「入力しながら 1 つ選ぶ」までをひとまとまりとして Google に数えさせる
  /// ためのもの。会場を選んだら呼び出し側で新しいトークンに切り替える。
  Future<List<VenueSuggestion>> search(String term, {String? sessionToken}) {
    final query = term.trim();
    if (query.length < minQueryLength) return Future.value(const []);

    final cached = _cache.remove(query);
    if (cached != null) {
      _cache[query] = cached;
      return Future.value(cached);
    }
    final pending = _inFlight[query];
    if (pending != null) return pending;

    final request = _fetch(query, sessionToken);
    _inFlight[query] = request;
    return request
        .then((venues) {
          _cache[query] = venues;
          if (_cache.length > _maxCacheEntries) {
            _cache.remove(_cache.keys.first);
          }
          return venues;
        })
        .whenComplete(() => _inFlight.remove(query));
  }

  Future<List<VenueSuggestion>> _fetch(
    String query,
    String? sessionToken,
  ) async {
    final data = await invokeEdgeFunction(
      _functions,
      'venue-search',
      body: {
        'query': query,
        if (sessionToken != null) 'sessionToken': sessionToken,
      },
      messageForError: messageForError,
      timeout: const Duration(seconds: 15),
    );
    if (data is! Map || data['venues'] is! List) {
      throw const UserFacingException('候補の形式が想定外でした。');
    }
    return [
      for (final v in data['venues'] as List) ?VenueSuggestion.tryParse(v),
    ];
  }

  @visibleForTesting
  static String messageForError(Object? code, int status) => switch (code) {
    'venue_search_not_configured' => '会場の検索は現在ご利用いただけません。',
    'venue_search_rate_limited' => '会場の検索が混み合っています。少し待ってからお試しください。',
    'venue_search_timeout' => '会場の情報の取得に時間がかかっています。少し待ってからお試しください。',
    _ => '会場の情報を取得できませんでした ($status)。',
  };
}
