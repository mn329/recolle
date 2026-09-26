import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_timeline.dart';

/// ランキングの 1 行。
typedef RankedItem = ({String label, int count});

/// 振り返りの集計結果。対象は今日より前の記録（実際に行った・観たもの）だけ。
class RecordStats {
  const RecordStats({
    required this.liveCount,
    required this.liveCountsByFormat,
    required this.artistCount,
    required this.countsByType,
    required this.totalTicketPrice,
    required this.pricedLiveCount,
    required this.liveCountsByMonth,
    required this.topArtists,
    required this.topVenues,
    required this.topSongs,
    required this.lives,
  });

  final int liveCount;

  /// ワンマン・対バン・フェスそれぞれのライブ数。
  final Map<EventFormat, int> liveCountsByFormat;

  /// 観たアーティストの数（対バン・フェスの出演者も含む）。
  final int artistCount;

  final Map<RecordType, int> countsByType;

  /// チケット代を入力したライブの合計（円）。
  final int totalTicketPrice;

  /// チケット代を入力したライブの数。平均の分母に使う。
  final int pricedLiveCount;

  /// 1〜12 月のライブ数（添字 0 が 1 月）。年を指定しないときは全期間の月別合計。
  final List<int> liveCountsByMonth;

  final List<RankedItem> topArtists;
  final List<RankedItem> topVenues;

  /// セットリストに登場した回数の多い曲。アーティストで絞ったときはその人の曲だけ。
  final List<RankedItem> topSongs;

  /// 集計対象のライブ（新しい順）。
  final List<Record> lives;

  /// 最初に行ったライブの日。
  DateTime? get firstLiveDate => lives.isEmpty ? null : lives.last.date;

  /// 最後に行ったライブの日。
  DateTime? get lastLiveDate => lives.isEmpty ? null : lives.first.date;

  int? get averageTicketPrice => pricedLiveCount == 0
      ? null
      : (totalTicketPrice / pricedLiveCount).round();

  bool get isEmpty => countsByType.values.every((c) => c == 0);
}

/// 記録がある年を新しい順に返す（今日より前の記録のみ）。
List<int> yearsWithRecords(Iterable<Record> records, DateTime now) {
  final years = {for (final r in splitByDate(records, now).past) r.date.year};
  return years.toList()..sort((a, b) => b.compareTo(a));
}

/// [artist] の記録だけに絞る。対バン・フェスやコラボ表記（「A × B」など）の記録も含める。
/// null なら絞らない。
List<Record> filterByArtist(Iterable<Record> records, String? artist) => [
  for (final r in records)
    if (artist == null || r.features(artist)) r,
];

/// [year] が null なら全期間を集計する。ランキングは各 [rankingLimit] 件まで。
/// [artist] を渡すと、曲のランキングは対バン・フェスでもその出演者の曲だけを数える。
RecordStats computeStats(
  Iterable<Record> records, {
  required DateTime now,
  int? year,
  String? artist,
  int rankingLimit = 5,
}) {
  final past = splitByDate(
    records,
    now,
  ).past.where((r) => year == null || r.date.year == year);
  final lives = past.where((r) => r.type == RecordType.live).toList();

  final countsByType = {for (final t in RecordType.values) t: 0};
  for (final r in past) {
    countsByType[r.type] = countsByType[r.type]! + 1;
  }

  final byFormat = {for (final f in EventFormat.values) f: 0};
  final byMonth = List.filled(12, 0);
  var total = 0;
  var priced = 0;
  final artists = _Counter();
  final venues = _Counter();
  final songs = _Counter();
  for (final r in lives) {
    byFormat[r.eventFormat] = byFormat[r.eventFormat]! + 1;
    byMonth[r.date.month - 1]++;
    if (r.ticketPrice != null) {
      total += r.ticketPrice!;
      priced++;
    }
    // 対バン・フェスは出演者全員を「観た」として数える
    final performers = {
      for (final a in r.performances)
        if (a.artist.trim().isNotEmpty) normalizeArtistName(a.artist): a.artist,
    };
    performers.values.forEach(artists.add);
    if (r.venue != null) venues.add(r.venue!);
    // 同じ公演で 2 回演奏された曲（アンコール等）は 1 回として数える
    final uniqueSongs = artist == null
        ? {for (final a in r.performances) ...a.songs}
        : r.songsBy(artist).toSet();
    uniqueSongs.forEach(songs.add);
  }

  return RecordStats(
    liveCount: lives.length,
    liveCountsByFormat: byFormat,
    artistCount: artists.length,
    countsByType: countsByType,
    totalTicketPrice: total,
    pricedLiveCount: priced,
    liveCountsByMonth: byMonth,
    topArtists: artists.top(rankingLimit),
    topVenues: venues.top(rankingLimit),
    topSongs: songs.top(rankingLimit),
    lives: lives,
  );
}

/// 大文字小文字・空白の違いをまとめて数え、いちばん多い表記で表示する。
class _Counter {
  final _counts = <String, int>{};
  final _spellings = <String, Map<String, int>>{};

  int get length => _counts.length;

  void add(String raw) {
    final label = raw.trim();
    if (label.isEmpty) return;
    final key = normalizeArtistName(label);
    _counts[key] = (_counts[key] ?? 0) + 1;
    final spellings = _spellings.putIfAbsent(key, () => {});
    spellings[label] = (spellings[label] ?? 0) + 1;
  }

  String _labelFor(String key) {
    final entries = _spellings[key]!.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries.first.key;
  }

  List<RankedItem> top(int limit) {
    final ranked =
        [
          for (final e in _counts.entries)
            (label: _labelFor(e.key), count: e.value),
        ]..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          if (byCount != 0) return byCount;
          // 同数なら大文字小文字を区別せずに並べ、小文字の表記が常に後ろへ回らないようにする
          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        });
    return ranked.take(limit).toList();
  }
}
