import 'dart:async';

import 'package:flutter/foundation.dart';
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

  final cached = await cache.load(userId);
  if (!online) {
    yield cached;
    return;
  }

  // 端末はつながっていてもサーバーに届かないこと（会場の Wi-Fi など）があるので、
  // 手元の記録を先に出しておく。取得に失敗しても AsyncError が直前の値を持つので、画面は一覧を残せる
  if (cached.isNotEmpty) yield cached;

  yield* Supabase.instance.client
      .from('records')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .order('date', ascending: false)
      .map((maps) {
        final records = maps.map((map) => Record.fromJson(map)).toList();
        unawaited(
          cache.save(userId, records).catchError((Object e) {
            debugPrint('Records cache save failed: $e');
          }),
        );
        return records;
      });
});
