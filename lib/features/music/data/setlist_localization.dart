import 'package:flutter/foundation.dart';
import 'package:recolle/features/music/data/itunes_client.dart';

/// setlist.fm の曲目を、iTunes で見つかった日本語の曲名に置き換える。
///
/// setlist.fm の日本の曲名はローマ字で登録されがちなため。日本語化は補助機能なので、
/// 見つからない曲や通信に失敗したときは元の表記のまま返す。
Future<List<String>> localizeSetlistSongs(
  ItunesClient itunes, {
  required String artistName,
  required List<String> songs,
}) async {
  try {
    final japanese = await itunes.localizeSongTitles(
      artistName: artistName,
      titles: songs,
    );
    return [for (final s in songs) japanese[s] ?? s];
  } catch (e) {
    debugPrint('Song title localization failed: $e');
    return songs;
  }
}
