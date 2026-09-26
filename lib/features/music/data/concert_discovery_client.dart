import 'package:flutter/foundation.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 生成 AI が Web 検索で見つけた今後の公演。告知と違うことがあるので、登録前に確認してもらう。
@immutable
class DiscoveredConcert {
  const DiscoveredConcert({
    required this.title,
    required this.date,
    this.openTime,
    this.startTime,
    this.venue,
    this.city,
    this.sourceUrl,
  });

  /// 形式が壊れていれば null。サーバーでも検めているが、アプリ側でも信用しない。
  static DiscoveredConcert? tryParse(Map<String, dynamic> json) {
    final title = _text(json['title']);
    final date = DateTime.tryParse(_text(json['date']) ?? '');
    if (title == null || date == null) return null;
    final source = Uri.tryParse(_text(json['sourceUrl']) ?? '');
    return DiscoveredConcert(
      title: title,
      date: DateTime(date.year, date.month, date.day),
      openTime: ClockTime.tryParse(_text(json['openTime'])),
      startTime: ClockTime.tryParse(_text(json['startTime'])),
      venue: _text(json['venue']),
      city: _text(json['city']),
      sourceUrl: source != null && source.isScheme('https') ? source : null,
    );
  }

  final String title;
  final DateTime date;
  final ClockTime? openTime;
  final ClockTime? startTime;
  final String? venue;
  final String? city;
  final Uri? sourceUrl;

  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}

/// 検索で参照したページ（Google のリダイレクト URL とドメイン名）。
typedef DiscoverySource = ({String title, Uri uri});

@immutable
class ConcertDiscoveryResult {
  const ConcertDiscoveryResult({
    required this.concerts,
    required this.sources,
    required this.fetchedAt,
    this.searchEntryPoint,
  });

  factory ConcertDiscoveryResult.fromJson(Map<String, dynamic> json) {
    return ConcertDiscoveryResult(
      concerts: [
        for (final e in json['events'] as List? ?? const [])
          if (e is Map)
            ?DiscoveredConcert.tryParse(Map<String, dynamic>.from(e)),
      ],
      sources: [
        for (final s in json['sources'] as List? ?? const []) ?_parseSource(s),
      ],
      fetchedAt:
          DateTime.tryParse(
            DiscoveredConcert._text(json['fetchedAt']) ?? '',
          )?.toLocal() ??
          DateTime.now(),
      searchEntryPoint: DiscoveredConcert._text(json['searchEntryPoint']),
    );
  }

  final List<DiscoveredConcert> concerts;
  final List<DiscoverySource> sources;
  final DateTime fetchedAt;

  /// Google 検索の候補（HTML）。規約上、検索結果を見せるときは一緒に表示する。
  final String? searchEntryPoint;

  static DiscoverySource? _parseSource(Object? json) {
    if (json is! Map) return null;
    final title = json['title'];
    final rawUri = json['uri'];
    final uri = rawUri is String ? Uri.tryParse(rawUri) : null;
    if (title is! String || uri == null || !uri.isScheme('https')) return null;
    return (title: title, uri: uri);
  }
}

/// Edge Function `concert-discovery` 経由で、アーティストの今後の公演を探す。
class ConcertDiscoveryClient {
  ConcertDiscoveryClient(this._functions);

  final FunctionsClient _functions;

  Future<ConcertDiscoveryResult> discover(String artistName) async {
    final artist = artistName.trim();
    if (artist.isEmpty) {
      throw const UserFacingException('アーティスト名が空です。');
    }
    try {
      final res = await _functions.invoke(
        'concert-discovery',
        body: {'artistName': artist},
      );
      final data = res.data;
      if (data is! Map) {
        throw const UserFacingException('公演情報の形式が想定外でした。');
      }
      return ConcertDiscoveryResult.fromJson(Map<String, dynamic>.from(data));
    } on FunctionException catch (e) {
      final code = e.details is Map ? (e.details as Map)['error'] : null;
      throw UserFacingException(messageForError(code, e.status));
    }
  }

  @visibleForTesting
  static String messageForError(Object? code, int status) => switch (code) {
    'discovery_not_configured' =>
      '公演検索が未設定です（サーバーに Gemini の API キーが登録されていません）。',
    'discovery_daily_limit' => '今日の公演検索の上限に達しました。明日またお試しください。',
    'discovery_rate_limited' => '検索が混み合っています。少し待ってからお試しください。',
    'discovery_timeout' => '検索に時間がかかりすぎました。もう一度お試しください。',
    'discovery_parse_error' => '検索結果をうまく読み取れませんでした。もう一度お試しください。',
    _ => '公演を検索できませんでした ($status)。',
  };
}
