import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/data/setlistfm_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final itunesClientProvider = Provider<ItunesClient>((ref) => ItunesClient());

final setlistFmClientProvider = Provider<SetlistFmClient>(
  (ref) => SetlistFmClient(Supabase.instance.client.functions),
);

/// アーティスト名ごとのアートワーク。見つからない・失敗時は null（画像なし表示）。
final artistArtworkProvider = FutureProvider.family<String?, String>((
  ref,
  artistName,
) async {
  ref.keepAlive();
  return ref.read(itunesClientProvider).findArtistArtwork(artistName);
});
