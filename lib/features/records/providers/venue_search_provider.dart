import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/features/records/data/venue_search_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final venueSearchClientProvider = Provider<VenueSearchClient>(
  (ref) => VenueSearchClient(Supabase.instance.client.functions),
);

/// 地図（Google Places）からの会場検索を使うか。
///
/// 本番に `venue-search` 関数と `GOOGLE_PLACES_API_KEY` を用意し、呼び出し回数の上限を設けるまでは
/// `false` にしておく。`false` の間は過去の記録からの候補だけが出て、サーバーには問い合わせない。
const bool kVenueMapSearchEnabled = false;
