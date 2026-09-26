import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SetlistSummary {
  const SetlistSummary({
    required this.id,
    required this.eventDate,
    required this.artistName,
    required this.venueName,
    required this.cityName,
    required this.songs,
    this.tourName,
  });

  factory SetlistSummary.fromJson(Map<String, dynamic> json) {
    return SetlistSummary(
      id: json['id'] as String,
      eventDate: _parseSetlistFmDate(json['eventDate'] as String? ?? ''),
      artistName: json['artistName'] as String? ?? '',
      venueName: json['venueName'] as String? ?? '',
      cityName: json['cityName'] as String? ?? '',
      tourName: json['tourName'] as String?,
      songs: [
        for (final s in json['songs'] as List? ?? const [])
          if (s is String) s,
      ],
    );
  }

  final String id;
  final DateTime? eventDate;
  final String artistName;
  final String venueName;
  final String cityName;
  final String? tourName;
  final List<String> songs;

  /// setlist.fm の日付は dd-MM-yyyy。
  static DateTime? _parseSetlistFmDate(String raw) {
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    return DateTime(y, m, d);
  }
}

/// Edge Function `setlistfm-search` 経由で setlist.fm を検索する。
class SetlistFmClient {
  SetlistFmClient(this._functions);

  final FunctionsClient _functions;

  Future<List<SetlistSummary>> search({
    required String artistName,
    DateTime? date,
  }) async {
    final artist = artistName.trim();
    if (artist.isEmpty) return const [];

    try {
      final res = await _functions.invoke(
        'setlistfm-search',
        body: {'artistName': artist, if (date != null) 'date': _isoDate(date)},
      );
      final data = res.data;
      if (data is! Map || data['setlists'] is! List) {
        throw const UserFacingException('セットリストの形式が想定外でした。');
      }
      return [
        for (final s in data['setlists'] as List)
          if (s is Map) SetlistSummary.fromJson(Map<String, dynamic>.from(s)),
      ];
    } on FunctionException catch (e) {
      final code = e.details is Map ? (e.details as Map)['error'] : null;
      throw UserFacingException(switch (code) {
        'setlistfm_not_configured' =>
          'setlist.fm 連携が未設定です（サーバーに API キーが登録されていません）。',
        'setlistfm_rate_limited' => 'setlist.fm が混み合っています。少し待ってからお試しください。',
        'setlistfm_timeout' => 'setlist.fm の応答がタイムアウトしました。',
        _ => 'セットリストを取得できませんでした (${e.status})。',
      });
    }
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
