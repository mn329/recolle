import 'package:flutter/foundation.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/features/music/data/concert_discovery_client.dart';
import 'package:recolle/features/music/data/setlistfm_client.dart';
import 'package:recolle/features/records/models/record.dart';

/// 候補の出どころ。選んだときにどこまで入力するかが変わる。
enum ConcertCandidateSource {
  /// 公演検索（生成 AI）で見つけた今後の公演。
  upcoming,

  /// setlist.fm に登録された公演。
  setlistFm,

  /// 自分の過去の記録。ツアーの別日を記録するときに公演名だけ使う。
  record,
}

/// 作成画面の公演名欄に出す候補。
@immutable
class ConcertCandidate {
  const ConcertCandidate({
    required this.title,
    required this.source,
    this.date,
    this.venue,
    this.city,
    this.openTime,
    this.startTime,
    this.songs = const [],
  });

  final String title;
  final ConcertCandidateSource source;
  final DateTime? date;
  final String? venue;
  final String? city;
  final ClockTime? openTime;
  final ClockTime? startTime;
  final List<String> songs;

  /// 日付・会場などを入力してよいか。過去の記録は別の日の公演なので公演名だけにする。
  bool get fillsDetails => source != ConcertCandidateSource.record;
}

/// 出どころごとの件数の上限。一覧はスクロールできるが、際限なく並べない。
const _maxPerSource = 20;

/// [query] で絞り込んだ候補。今後の公演・setlist.fm・過去の記録の順に並べる。
///
/// [query] が空なら絞り込まない。同じ日の同じ公演名は 1 件にまとめる。
/// [searchedSetlists] は [query] で setlist.fm を検索した結果。setlist.fm 側の
/// あいまい一致を信じ、ここでは絞り込まずに直近の公演の後ろへ並べる。
List<ConcertCandidate> buildConcertCandidates({
  required String query,
  required String artist,
  Iterable<DiscoveredConcert> upcoming = const [],
  Iterable<SetlistSummary> setlists = const [],
  Iterable<SetlistSummary> searchedSetlists = const [],
  Iterable<Record> records = const [],
}) {
  final q = normalizeArtistName(query);
  bool matches(ConcertCandidate c) =>
      q.isEmpty ||
      [
        c.title,
        c.venue,
        c.city,
      ].any((text) => text != null && normalizeArtistName(text).contains(q));

  final fromUpcoming = [
    for (final c in upcoming)
      ConcertCandidate(
        title: c.title,
        source: ConcertCandidateSource.upcoming,
        date: c.date,
        venue: c.venue,
        city: c.city,
        openTime: c.openTime,
        startTime: c.startTime,
      ),
  ];
  List<ConcertCandidate> fromSetlistFm(Iterable<SetlistSummary> items) => [
    for (final s in items)
      if (s.eventDate != null)
        ConcertCandidate(
          // ツアー名のない単発公演は会場名で呼び分ける
          title:
              s.tourName ?? '${s.venueName.isEmpty ? artist : s.venueName} 公演',
          source: ConcertCandidateSource.setlistFm,
          date: s.eventDate,
          venue: s.venueName.isEmpty ? null : s.venueName,
          city: s.cityName.isEmpty ? null : s.cityName,
          songs: s.songs,
        ),
  ];
  final pastTitles = <String>{};
  final fromRecords = [
    for (final r
        in records
            .where((r) => r.type == RecordType.live && r.features(artist))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date)))
      if (pastTitles.add(normalizeArtistName(r.title)))
        ConcertCandidate(
          title: r.title,
          source: ConcertCandidateSource.record,
          date: r.date,
          venue: r.venue,
        ),
  ];

  final seen = <String>{};
  return [
    ...fromUpcoming.where(matches).take(_maxPerSource),
    ...fromSetlistFm(setlists).where(matches).take(_maxPerSource),
    ...fromSetlistFm(searchedSetlists).take(_maxPerSource),
    ...fromRecords.where(matches).take(_maxPerSource),
  ].where((c) {
    final day = c.date == null
        ? ''
        : '${c.date!.year}-${c.date!.month}-${c.date!.day}';
    return seen.add('$day|${normalizeArtistName(c.title)}');
  }).toList();
}
