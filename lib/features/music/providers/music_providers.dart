import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:recolle/features/music/data/concert_discovery_client.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/data/preview_player.dart';
import 'package:recolle/features/music/data/setlistfm_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final itunesClientProvider = Provider<ItunesClient>((ref) => ItunesClient());

final setlistFmClientProvider = Provider<SetlistFmClient>(
  (ref) => SetlistFmClient(Supabase.instance.client.functions),
);

final concertDiscoveryClientProvider = Provider<ConcertDiscoveryClient>(
  (ref) => ConcertDiscoveryClient(Supabase.instance.client.functions),
);

/// アーティストの今後の公演。無料枠を使うので、ユーザーが「探す」を押してから読む。
///
/// 失敗しても自動では再試行しない（1 回ごとに Gemini の無料枠を消費するため）。
final concertDiscoveryProvider =
    FutureProvider.family<ConcertDiscoveryResult, String>(
      (ref, artistName) =>
          ref.read(concertDiscoveryClientProvider).discover(artistName),
      retry: (_, _) => null,
    );

/// setlist.fm に登録されたアーティストの直近の公演（新しい順に最大 20 件）。
/// 曲が未登録の公演も含む。
///
/// setlist.fm は呼び出し回数の制限が厳しいため、失敗しても自動では再試行しない。
final recentSetlistsProvider =
    FutureProvider.family<List<SetlistSummary>, String>(
      (ref, artistName) => ref
          .read(setlistFmClientProvider)
          .search(artistName: artistName, includeEmpty: true),
      retry: (_, _) => null,
    );

/// 試聴プレイヤー。見ている画面がなくなると破棄され、再生も止まる。
final previewPlayerProvider = ChangeNotifierProvider.autoDispose<PreviewPlayer>(
  (ref) => PreviewPlayer(),
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
