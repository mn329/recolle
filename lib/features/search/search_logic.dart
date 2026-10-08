import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/records/models/record.dart';

/// 空白区切りの各語をすべて含むか（AND 検索）。大文字小文字・空白の違いは無視する。
List<String> _tokens(String query) => query
    .split(RegExp(r'[\s\u3000]+'))
    .map(normalizeArtistName)
    .where((t) => t.isNotEmpty)
    .toList();

bool _containsAll(String text, List<String> tokens) {
  final normalized = normalizeArtistName(text);
  return tokens.every(normalized.contains);
}

class RecordSearchHit {
  const RecordSearchHit({required this.record, this.matchLabel, this.snippet});

  final Record record;

  /// タイトル・アーティスト以外で当たったときの項目名（例: "セトリ"）。
  final String? matchLabel;
  final String? snippet;
}

/// 自分の記録から探す。タイトル・アーティストでの一致を先に並べる。
List<RecordSearchHit> searchRecords(List<Record> records, String query) {
  final tokens = _tokens(query);
  if (tokens.isEmpty) return const [];

  final primary = <RecordSearchHit>[];
  final secondary = <RecordSearchHit>[];
  for (final record in records) {
    final performances = record.performances;
    final artistText = [for (final a in performances) a.artist].join('\n');
    final fields = <(String, String?)>[
      ('セトリ', [for (final a in performances) ...a.songs].join('\n')),
      ('MCメモ', record.mcMemo),
      ('感想', record.impressions),
      ('取得元', record.ticketSource),
    ];
    final allText = [
      record.title,
      artistText,
      for (final (_, value) in fields) ?value,
    ].join('\n');
    if (!_containsAll(allText, tokens)) continue;

    if (_containsAll('${record.title}\n$artistText', tokens)) {
      primary.add(RecordSearchHit(record: record));
      continue;
    }
    // 補足表示用に、いずれかの語を含む最初の行を抜き出す
    (String, String)? match;
    for (final (label, value) in fields) {
      if (value == null) continue;
      final line = value
          .split('\n')
          .where((l) => tokens.any(normalizeArtistName(l).contains))
          .firstOrNull;
      if (line != null) {
        match = (label, line.trim());
        break;
      }
    }
    secondary.add(
      RecordSearchHit(
        record: record,
        matchLabel: match?.$1,
        snippet: match?.$2,
      ),
    );
  }
  return [...primary, ...secondary];
}

class LocalArtist {
  const LocalArtist({
    required this.name,
    required this.recordCount,
    this.favorite,
  });

  final String name;
  final int recordCount;
  final FavoriteArtist? favorite;
}

/// 記録とお気に入りに出てくるアーティスト。[query] が空なら全件。記録の多い順。
List<LocalArtist> searchLocalArtists({
  required List<Record> records,
  required List<FavoriteArtist> favorites,
  required String query,
}) {
  final tokens = _tokens(query);
  final byKey = <String, LocalArtist>{};

  for (final f in favorites) {
    byKey[normalizeArtistName(f.name)] = LocalArtist(
      name: f.name,
      recordCount: records.where((r) => r.features(f.name)).length,
      favorite: f,
    );
  }
  final liveRecords = records.where((r) => r.type == RecordType.live);
  final performerCounts = <String, int>{};
  final performerNames = <String, String>{};
  for (final r in liveRecords) {
    final keys = <String>{};
    for (final a in r.performances) {
      final key = normalizeArtistName(a.artist);
      if (key.isEmpty || !keys.add(key)) continue;
      performerNames.putIfAbsent(key, () => a.artist.trim());
      performerCounts[key] = (performerCounts[key] ?? 0) + 1;
    }
  }
  for (final MapEntry(:key, value: count) in performerCounts.entries) {
    if (byKey.containsKey(key)) continue;
    byKey[key] = LocalArtist(name: performerNames[key]!, recordCount: count);
  }

  return byKey.values.where((a) => _containsAll(a.name, tokens)).toList()
    ..sort((a, b) {
      final byCount = b.recordCount.compareTo(a.recordCount);
      return byCount != 0 ? byCount : a.name.compareTo(b.name);
    });
}

class LocalSong {
  const LocalSong({
    required this.title,
    required this.artistName,
    required this.timesHeard,
    required this.lastHeard,
  });

  final String title;
  final String artistName;
  final int timesHeard;
  final DateTime lastHeard;
}

/// ライブ記録のセトリに出てくる曲。[query] が空なら全件。聴いた回数の多い順。
///
/// 曲名だけでなく「曲名 アーティスト」の組み合わせでも当たる。
List<LocalSong> searchLocalSongs(List<Record> records, String query) {
  final tokens = _tokens(query);
  final byKey = <(String, String), LocalSong>{};

  for (final r in records.where((r) => r.type == RecordType.live)) {
    for (final act in r.performances) {
      for (final title in act.songTitles.toSet()) {
        final key = (
          normalizeArtistName(act.artist),
          normalizeArtistName(title),
        );
        final existing = byKey[key];
        byKey[key] = LocalSong(
          title: existing?.title ?? title,
          artistName: existing?.artistName ?? act.artist.trim(),
          timesHeard: (existing?.timesHeard ?? 0) + 1,
          lastHeard: existing == null || r.date.isAfter(existing.lastHeard)
              ? r.date
              : existing.lastHeard,
        );
      }
    }
  }

  return byKey.values
      .where((s) => _containsAll('${s.title}\n${s.artistName}', tokens))
      .toList()
    ..sort((a, b) {
      final byCount = b.timesHeard.compareTo(a.timesHeard);
      return byCount != 0 ? byCount : b.lastHeard.compareTo(a.lastHeard);
    });
}
