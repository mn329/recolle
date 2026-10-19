import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_timeline.dart';

/// ランキングの 1 行。
typedef RankedItem = ({String label, int count});

/// 曲のランキングの 1 行。同じ曲名でもアーティストが違えば別の曲として数える。
typedef RankedSong = ({String title, String artist, int count});

/// 振り返りの集計結果。登録した記録はこれからの予定も含めてすべて数える（チケット代などの家計簿を兼ねるため）。
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
    required this.firstLiveDate,
    required this.lastLiveDate,
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
  final List<RankedSong> topSongs;

  /// 集計対象のライブ（新しい順）。
  final List<Record> lives;

  /// 最初に行ったライブの日。これからの予定は含めない。
  final DateTime? firstLiveDate;

  /// 最後に行ったライブの日。これからの予定は含めない。
  final DateTime? lastLiveDate;

  int? get averageTicketPrice => pricedLiveCount == 0
      ? null
      : (totalTicketPrice / pricedLiveCount).round();

  bool get isEmpty => countsByType.values.every((c) => c == 0);
}

/// 記録がある年を新しい順に返す（これからの予定の年も含む）。
List<int> yearsWithRecords(Iterable<Record> records) {
  final years = {for (final r in records) r.date.year};
  return years.toList()..sort((a, b) => b.compareTo(a));
}

/// [year] が null なら全期間。日付の新しい順に並べる。
List<Record> _inYear(Iterable<Record> records, int? year) => [
  for (final r in records)
    if (year == null || r.date.year == year) r,
]..sort((a, b) => b.startsAt.compareTo(a.startsAt));

/// ジャンル（[type]）の記録だけに絞る。null なら絞らない。
List<Record> filterByType(Iterable<Record> records, RecordType? type) => [
  for (final r in records)
    if (type == null || r.type == type) r,
];

/// [artist] の記録だけに絞る。対バン・フェスやコラボ表記（「A × B」など）の記録も含める。
/// null なら絞らない。
List<Record> filterByArtist(Iterable<Record> records, String? artist) => [
  for (final r in records)
    if (artist == null || r.features(artist)) r,
];

/// 会場が [venue] の記録だけに絞る（大文字小文字・空白の違いはまとめる。集計の会場ランキングと同じ）。
List<Record> filterByVenue(Iterable<Record> records, String venue) {
  final key = normalizeArtistName(venue);
  return [
    for (final r in records)
      if (r.venue case final v? when normalizeArtistName(v) == key) r,
  ];
}

/// [year] が null なら全期間を集計する。[now] は、行ったライブとこれからの予定を分けるのに使う。ランキングは各 [rankingLimit] 件まで。
/// [artist] を渡すと、曲のランキングは対バン・フェスでもその出演者の曲だけを数える。
RecordStats computeStats(
  Iterable<Record> records, {
  required DateTime now,
  int? year,
  String? artist,
  int rankingLimit = 5,
}) {
  final counted = _inYear(records, year);
  final lives = counted.where((r) => r.type == RecordType.live).toList();
  final pastLives = splitByDate(lives, now).past;

  final countsByType = {for (final t in RecordType.values) t: 0};
  for (final r in counted) {
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
    // 同じ公演で同じ出演者が 2 回演奏した曲（アンコール等）は 1 回として数える
    final played = <String>{};
    for (final a in r.performances) {
      if (artist != null && !artistMatches(a.artist, artist)) continue;
      for (final song in a.songTitles) {
        if (played.add(_Counter.keyFor(song, scope: a.artist))) {
          songs.add(song, scope: a.artist);
        }
      }
    }
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
    topSongs: songs.topSongs(rankingLimit),
    lives: lives,
    firstLiveDate: pastLives.lastOrNull?.date,
    lastLiveDate: pastLives.firstOrNull?.date,
  );
}

/// 1 ジャンルの件数・金額・月別・会場・一覧の集計。対象は登録したすべての記録（これからの予定も含む）。
///
/// ライブ以外のジャンル（映画・本・その他）の振り返りは、出演者やセトリがないのでこれだけを出す。
class GenreStats {
  const GenreStats({
    required this.type,
    required this.totalPrice,
    required this.pricedCount,
    required this.countsByMonth,
    required this.topVenues,
    required this.records,
  });

  final RecordType type;

  /// 価格（チケット代・本の価格）を入力した記録の合計（円）。
  final int totalPrice;

  /// 価格を入力した記録の数。平均の分母に使う。
  final int pricedCount;

  /// 1〜12 月の件数（添字 0 が 1 月）。年を指定しないときは全期間の月別合計。
  final List<int> countsByMonth;

  /// 場所の入力欄がないジャンル（本）では常に空。
  final List<RankedItem> topVenues;

  /// 集計対象の記録（新しい順）。
  final List<Record> records;

  int get count => records.length;

  int? get averagePrice =>
      pricedCount == 0 ? null : (totalPrice / pricedCount).round();

  bool get isEmpty => records.isEmpty;
}

/// [type] の記録を集計する（これからの予定も含む）。[year] が null なら全期間。会場のランキングは [rankingLimit] 件まで。
GenreStats computeGenreStats(
  Iterable<Record> records, {
  required RecordType type,
  int? year,
  int rankingLimit = 5,
}) {
  final list = [
    for (final r in _inYear(records, year))
      if (r.type == type) r,
  ];

  final byMonth = List.filled(12, 0);
  var total = 0;
  var priced = 0;
  final venues = _Counter();
  for (final r in list) {
    byMonth[r.date.month - 1]++;
    if (r.ticketPrice != null) {
      total += r.ticketPrice!;
      priced++;
    }
    if (type.venueLabel != null && r.venue != null) venues.add(r.venue!);
  }

  return GenreStats(
    type: type,
    totalPrice: total,
    pricedCount: priced,
    countsByMonth: byMonth,
    topVenues: venues.top(rankingLimit),
    records: list,
  );
}

/// 全ジャンルをまとめた集計。ジャンルごとの [GenreStats] を並べて持つ。
class OverviewStats {
  const OverviewStats(this.byType);

  /// [RecordType.values] の順。
  final List<GenreStats> byType;

  int get count => byType.fold(0, (sum, g) => sum + g.count);

  /// 価格（チケット代・本の価格）を入力した記録の合計（円）。
  int get totalPrice => byType.fold(0, (sum, g) => sum + g.totalPrice);

  int get pricedCount => byType.fold(0, (sum, g) => sum + g.pricedCount);

  int? get averagePrice =>
      pricedCount == 0 ? null : (totalPrice / pricedCount).round();

  /// 1〜12 月の件数（添字 0 が 1 月）。
  List<int> get countsByMonth => [
    for (var m = 0; m < 12; m++)
      byType.fold(0, (sum, g) => sum + g.countsByMonth[m]),
  ];

  bool get isEmpty => count == 0;
}

/// 全ジャンルの記録を集計する。[year] が null なら全期間。
OverviewStats computeOverviewStats(Iterable<Record> records, {int? year}) =>
    OverviewStats([
      for (final type in RecordType.values)
        computeGenreStats(records, type: type, year: year),
    ]);

/// 大文字小文字・空白の違いをまとめて数え、いちばん多い表記で表示する。
/// [add] に scope（曲ならアーティスト）を渡すと、scope ごとに別の項目として数える。
class _Counter {
  final _counts = <String, int>{};
  final _spellings = <String, Map<String, int>>{};
  final _scopeSpellings = <String, Map<String, int>>{};

  int get length => _counts.length;

  static String keyFor(String label, {String? scope}) => [
    if (scope != null) normalizeArtistName(scope),
    normalizeArtistName(label),
  ].join('\u0000');

  void add(String raw, {String? scope}) {
    final label = raw.trim();
    if (label.isEmpty) return;
    final key = keyFor(label, scope: scope);
    _counts[key] = (_counts[key] ?? 0) + 1;
    _countSpelling(_spellings, key, label);
    if (scope != null) _countSpelling(_scopeSpellings, key, scope.trim());
  }

  static void _countSpelling(
    Map<String, Map<String, int>> table,
    String key,
    String spelling,
  ) {
    final spellings = table.putIfAbsent(key, () => {});
    spellings[spelling] = (spellings[spelling] ?? 0) + 1;
  }

  static String _mostCommon(Map<String, int> spellings) {
    final entries = spellings.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries.first.key;
  }

  List<({String key, String label, int count})> _ranked(int limit) {
    final ranked =
        [
          for (final e in _counts.entries)
            (
              key: e.key,
              label: _mostCommon(_spellings[e.key]!),
              count: e.value,
            ),
        ]..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          if (byCount != 0) return byCount;
          // 同数なら大文字小文字を区別せずに並べ、小文字の表記が常に後ろへ回らないようにする
          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        });
    return ranked.take(limit).toList();
  }

  List<RankedItem> top(int limit) => [
    for (final r in _ranked(limit)) (label: r.label, count: r.count),
  ];

  List<RankedSong> topSongs(int limit) => [
    for (final r in _ranked(limit))
      (
        title: r.label,
        artist: _mostCommon(_scopeSpellings[r.key] ?? const {'': 0}),
        count: r.count,
      ),
  ];
}
