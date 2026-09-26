import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/data/setlistfm_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final itunesClientProvider = Provider<ItunesClient>((ref) => ItunesClient());

final setlistFmClientProvider = Provider<SetlistFmClient>(
  (ref) => SetlistFmClient(Supabase.instance.client.functions),
);

typedef ArtistQuery = ({String name, int? itunesArtistId});
typedef SongQuery = ({String artistName, String title});

/// iTunes 上のアーティスト。見つからなければ null（リンクは検索 URL で代用）。
final itunesArtistProvider = FutureProvider.family<ItunesArtist?, ArtistQuery>((
  ref,
  query,
) {
  return ref
      .read(itunesClientProvider)
      .findArtist(query.name, artistId: query.itunesArtistId);
});

final topSongsProvider = FutureProvider.family<List<ItunesSong>, int>((
  ref,
  artistId,
) {
  return ref.read(itunesClientProvider).topSongs(artistId);
});

/// 記録の曲名に対応する iTunes の曲。見つからなければ null。
final itunesSongProvider = FutureProvider.family<ItunesSong?, SongQuery>((
  ref,
  query,
) {
  return ref
      .read(itunesClientProvider)
      .findSong(artistName: query.artistName, title: query.title);
});

/// アーティスト名ごとのアートワーク。見つからない・失敗時は null（画像なし表示）。
final artistArtworkProvider = FutureProvider.family<String?, String>((
  ref,
  artistName,
) async {
  ref.keepAlive();
  return ref.read(itunesClientProvider).findArtistArtwork(artistName);
});
