import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/ticket_mail_parser.dart';

/// 記録が少ないうちも候補が出るよう、ライブでよく使われる会場を添える。
/// 地図の検索が使えないとき（未設定・圏外）の受け皿でもある。
const _commonLiveVenues = [
  '東京ドーム',
  '日本武道館',
  'さいたまスーパーアリーナ',
  '横浜アリーナ',
  'Kアリーナ横浜',
  'ぴあアリーナMM',
  '有明アリーナ',
  '国立代々木競技場 第一体育館',
  '東京ガーデンシアター',
  '幕張メッセ',
  '日産スタジアム',
  '京セラドーム大阪',
  '大阪城ホール',
  'バンテリンドーム ナゴヤ',
  'みずほPayPayドーム福岡',
  'Zepp Haneda',
  'Zepp DiverCity',
];

/// 種別ごとの定番の取得元。取得元欄の選択肢の母集合でもある。
List<String> commonSources(RecordType type) => switch (type) {
  RecordType.live || RecordType.other => [
    ...ticketSiteNames,
    'ファンクラブ',
    '公式サイト',
    'チケトレ',
    '当日券',
    '招待',
    '友人から',
  ],
  RecordType.movie => ['劇場窓口', '劇場のサイト・アプリ', 'ムビチケ', '前売券', '招待券'],
  RecordType.book => ['書店', 'Amazon', '楽天ブックス', '電子書籍', '古本・フリマ', '図書館'],
};

/// 会場欄の候補。同じ種別の過去の記録で使った会場（よく使う順）に、地図から引いた候補、
/// ライブなら定番の会場を続ける。
///
/// [mapResults] は地図の検索（Google Places）が返した会場名。かな入力やローマ字でも当たるよう、
/// 入力中の文字での絞り込みは向こうに任せてそのまま並べる。
List<String> venueSuggestions({
  required Iterable<Record> records,
  required RecordType type,
  required String query,
  List<String> mapResults = const [],
  int limit = 8,
}) => _suggest(
  used: [
    for (final r in records)
      if (r.type == type) ?r.venue,
  ],
  unfiltered: mapResults,
  common: type == RecordType.live ? _commonLiveVenues : const [],
  query: query,
  limit: limit,
);

/// 取得元欄の候補。同じ種別の過去の記録で使った取得元（よく使う順）に、種別ごとの定番を続ける。
List<String> sourceSuggestions({
  required Iterable<Record> records,
  required RecordType type,
  required String query,
  int limit = 8,
}) => _suggest(
  used: [
    for (final r in records)
      if (r.type == type) ?r.ticketSource,
  ],
  common: commonSources(type),
  query: query,
  limit: limit,
);

/// 取得元欄の選択肢。過去の記録で使った取得元（よく使う順）に、種別ごとの定番を続ける。
///
/// [sourceSuggestions] と違い、入力中の文字では絞らず全部返す。一覧から選ばせるため。
/// [current] が一覧にない値（メールの取り込みや以前の自由入力）なら先頭に足す。
List<String> sourceOptions({
  required Iterable<Record> records,
  required RecordType type,
  String? current,
}) {
  final options = _suggest(
    used: [
      for (final r in records)
        if (r.type == type) ?r.ticketSource,
    ],
    common: commonSources(type),
    query: '',
    limit: null,
  );
  final value = current?.trim() ?? '';
  if (value.isEmpty) return options;
  final key = normalizeArtistName(value);
  if (options.any((o) => normalizeArtistName(o) == key)) return options;
  return [value, ...options];
}

/// [query] を含む候補（大文字小文字・空白の違いは無視）。入力済みの値そのものは出さない。
///
/// [unfiltered] は [query] での絞り込みをかけない候補で、[used] のすぐ後ろに並ぶ。
/// [limit] が null なら件数で切らない。
List<String> _suggest({
  required List<String> used,
  required List<String> common,
  required String query,
  required int? limit,
  List<String> unfiltered = const [],
}) {
  final counts = <String, int>{};
  final spellings = <String, String>{};
  for (final raw in used) {
    final value = raw.trim();
    final key = normalizeArtistName(value);
    if (key.isEmpty) continue;
    counts[key] = (counts[key] ?? 0) + 1;
    spellings.putIfAbsent(key, () => value);
  }
  // 同じ回数なら先に出てきた（一覧の上にある）ものを前にする
  final order = counts.keys.toList();
  final ranked = [...order]
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : order.indexOf(a) - order.indexOf(b);
    });
  final q = normalizeArtistName(query);
  final picked = <String>{};
  final result = <String>[];

  void add(String value, {required bool filter}) {
    final key = normalizeArtistName(value);
    if (key.isEmpty || key == q) return;
    if (filter && !key.contains(q)) return;
    if (!picked.add(key)) return;
    result.add(value);
  }

  for (final key in ranked) {
    add(spellings[key]!, filter: true);
  }
  for (final value in unfiltered) {
    add(value.trim(), filter: false);
  }
  for (final value in common) {
    add(value, filter: true);
  }
  return limit == null ? result : result.take(limit).toList();
}
