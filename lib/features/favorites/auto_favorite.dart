import 'package:flutter/foundation.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/records/models/record.dart';

/// ライブの記録を保存したときに、お気に入りへ自動で入れるアーティスト。
///
/// ワンマンはそのアーティスト、対バン・フェスはお目当て（★）の出演者だけ。
/// フェスの出演者を全員入れるとお気に入りが埋まってしまうため。
/// 編集では、元の記録から新しく加わったアーティストだけにする
/// （自分でお気に入りから外したアーティストを、保存し直すたびに戻さないため）。
List<String> artistsToAutoFavorite(
  Record saved, {
  Record? previous,
  required List<FavoriteArtist> favorites,
}) {
  final before = {
    if (previous != null)
      for (final name in _candidates(previous)) normalizeArtistName(name),
  };
  final seen = <String>{};
  return [
    for (final name in _candidates(saved))
      if (!before.contains(normalizeArtistName(name)) &&
          !favorites.any((f) => artistMatches(name, f.name)) &&
          seen.add(normalizeArtistName(name)))
        name,
  ];
}

Iterable<String> _candidates(Record record) {
  if (record.type != RecordType.live) return const [];
  final names = record.acts.isEmpty
      ? [record.artistOrAuthor]
      : [
          for (final a in record.acts)
            if (a.isMain) a.artist,
        ];
  return names.map((n) => n.trim()).where((n) => n.isNotEmpty);
}

/// [names] をお気に入りに追加し、追加できた名前を返す。
///
/// 記録の保存に付随する処理なので、1 組の追加に失敗しても残りは続け、記録の保存も失敗させない。
Future<List<String>> addAutoFavorites(
  List<String> names, {
  required Future<void> Function(String name) add,
}) async {
  final added = <String>[];
  for (final name in names) {
    try {
      await add(name);
      added.add(name);
    } catch (e) {
      debugPrint('Auto favorite failed for $name: $e');
    }
  }
  return added;
}
