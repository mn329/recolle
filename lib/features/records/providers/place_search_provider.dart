import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/features/records/data/place_search_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final placeSearchClientProvider = Provider<PlaceSearchClient>(
  (ref) => PlaceSearchClient(Supabase.instance.client.functions),
);
