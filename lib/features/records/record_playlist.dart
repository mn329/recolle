import 'package:flutter/foundation.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/records/models/record.dart';

/// 記録のセトリから作るプレイリストの中身。
@immutable
class RecordPlaylistPlan {
  const RecordPlaylistPlan({
    required this.songIds,
    required this.missingTitles,
  });

  /// セトリの順（対バン・フェスは出演者の順）に並べた Apple Music の曲 ID。
  final List<int> songIds;

  /// Apple Music で見つからなかった曲名。
  final List<String> missingTitles;
}

/// 記録のセトリの曲を Apple Music で探す。区切り・MC は除き、出演者ごとにそのアーティストの曲から探す。
Future<RecordPlaylistPlan> planRecordPlaylist(
  ItunesClient itunes,
  Record record,
) async {
  final acts = [
    for (final a in record.performances)
      if (a.artist.trim().isNotEmpty && a.songTitles.isNotEmpty) a,
  ];
  // 出演者ごとの検索は互いに待つ必要がないので同時に投げる
  final idsByAct = await Future.wait([
    for (final a in acts)
      itunes.findSongIds(artistName: a.artist, titles: a.songTitles),
  ]);
  final songIds = <int>[];
  final missing = <String>[];
  for (final (i, act) in acts.indexed) {
    for (final title in act.songTitles) {
      final id = idsByAct[i][title];
      if (id != null) {
        songIds.add(id);
      } else {
        missing.add(title);
      }
    }
  }
  return RecordPlaylistPlan(songIds: songIds, missingTitles: missing);
}

/// プレイリスト名。公演名と日付（例: 「ZEPP TOUR 2026.09.27」）。
String recordPlaylistName(Record record) {
  String two(int n) => n.toString().padLeft(2, '0');
  final d = record.date;
  return '${record.title.trim()} ${d.year}.${two(d.month)}.${two(d.day)}';
}

/// プレイリストの説明。出演者と会場。
String recordPlaylistDescription(Record record) => [
  record.artistOrAuthor.trim(),
  if (record.venue?.trim() case final venue? when venue.isNotEmpty) '@ $venue',
  '（recolle で作成）',
].where((s) => s.isNotEmpty).join(' ');
