import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/features/account/providers/auth_providers.dart';
import 'package:recolle/features/records/data/records_local_cache.dart';
import 'package:recolle/features/records/data/records_repository.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final recordsRepositoryProvider = Provider<RecordsRepository>((ref) {
  return RecordsRepository(Supabase.instance.client);
});

final recordsProvider = StreamProvider<List<Record>>((ref) async* {
  final authUser = ref.watch(authUserProvider).asData?.value;
  final userId = authUser?.id;
  if (userId == null) {
    yield const [];
    return;
  }

  final connectivityAsync = ref.watch(connectivityProvider);
  final online = connectivityAsync.maybeWhen(
    data: isConnectivityOnline,
    orElse: () => true,
  );

  final cache = RecordsLocalCache();

  if (!online) {
    yield await cache.load(userId);
    return;
  }

  yield* Supabase.instance.client
      .from('records')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .order('date', ascending: false)
      .asyncMap((maps) async {
        final records = maps.map((map) => Record.fromJson(map)).toList();
        await cache.save(userId, records);
        return records;
      });
});
