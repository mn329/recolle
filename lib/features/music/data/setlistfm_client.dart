import 'package:recolle/core/network/edge_function.dart';
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

  /// [tourName] を渡すとツアー名でも絞り込む。[includeEmpty] が true なら、
  /// 曲が未登録の公演（開催前など）も返す。[pages] は新しい順に何ページ（1 ページ
  /// 20 件、最大 5）取るか。ツアー名で絞るときは 1 ページだけになる。
  Future<List<SetlistSummary>> search({
    required String artistName,
    String? tourName,
    bool includeEmpty = false,
    int pages = 1,
  }) async {
    final artist = artistName.trim();
    if (artist.isEmpty) return const [];
    final tour = tourName?.trim() ?? '';

    final data = await invokeEdgeFunction(
      _functions,
      'setlistfm-search',
      body: {
        'artistName': artist,
        if (tour.isNotEmpty) 'tourName': tour,
        if (includeEmpty) 'includeEmpty': true,
        if (pages > 1) 'pages': pages,
      },
      messageForError: (code, status) => switch (code) {
        'setlistfm_not_configured' => 'セットリストの検索は現在ご利用いただけません。',
        'setlistfm_rate_limited' => 'セットリストの検索が混み合っています。少し待ってからお試しください。',
        'setlistfm_timeout' => 'セットリストの取得に時間がかかっています。少し待ってからお試しください。',
        _ => 'セットリストを取得できませんでした ($status)。',
      },
    );
    if (data is! Map || data['setlists'] is! List) {
      throw const UserFacingException('セットリストの形式が想定外でした。');
    }
    return [
      for (final s in data['setlists'] as List)
        if (s is Map) SetlistSummary.fromJson(Map<String, dynamic>.from(s)),
    ];
  }
}
