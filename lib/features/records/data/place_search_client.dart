import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 会場・映画館の候補。
class PlaceSuggestion {
  const PlaceSuggestion({required this.id, required this.name, this.address});

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) =>
      PlaceSuggestion(
        id: json['id'] as String,
        name: json['name'] as String,
        address: json['address'] as String?,
      );

  final String id;
  final String name;
  final String? address;
}

/// Edge Function `place-search` 経由で Google Places API を検索する。
class PlaceSearchClient {
  PlaceSearchClient(this._functions);

  final FunctionsClient _functions;

  Future<List<PlaceSuggestion>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final res = await _functions.invoke('place-search', body: {'query': q});
      final data = res.data;
      if (data is! Map || data['places'] is! List) {
        throw const UserFacingException('場所の形式が想定外でした。');
      }
      return [
        for (final p in data['places'] as List)
          if (p is Map) PlaceSuggestion.fromJson(Map<String, dynamic>.from(p)),
      ];
    } on FunctionException catch (e) {
      final code = e.details is Map ? (e.details as Map)['error'] : null;
      throw UserFacingException(switch (code) {
        'places_not_configured' => '場所の検索が未設定です（サーバーに API キーが登録されていません）。',
        'places_timeout' => '場所の検索がタイムアウトしました。',
        _ => '場所を検索できませんでした (${e.status})。',
      });
    }
  }
}
