import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:recolle/core/app_update/app_version.dart';
import 'package:recolle/core/demo/demo_mode.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 強制アップデートの判定に使う値の取り出し口。テストでは差し替える。
abstract interface class ForceUpdateSource {
  /// 動いているアプリのバージョン（`1.1.4` など。ビルド番号は含まない）
  Future<String> currentVersion();

  /// 最低バージョン。確認しない環境や、サーバーに値がないときは null
  Future<String?> minimumVersion();
}

class SupabaseForceUpdateSource implements ForceUpdateSource {
  const SupabaseForceUpdateSource();

  @override
  Future<String> currentVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  @override
  Future<String?> minimumVersion() async {
    // 配信しているのは App Store だけ。スクリーンショット撮影中も止めない
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS || kDemoMode) {
      return null;
    }
    final row = await Supabase.instance.client
        .from('app_config')
        .select('min_ios_version')
        .maybeSingle();
    return row?['min_ios_version'] as String?;
  }
}

final forceUpdateSourceProvider = Provider<ForceUpdateSource>(
  (ref) => const SupabaseForceUpdateSource(),
);

/// アップデートが必要（true）か。起動時に確認し、[ForceUpdateNotifier.check] で確認し直す。
final forceUpdateProvider = NotifierProvider<ForceUpdateNotifier, bool>(
  ForceUpdateNotifier.new,
);

class ForceUpdateNotifier extends Notifier<bool> {
  static const _timeout = Duration(seconds: 5);

  @override
  bool build() {
    unawaited(check());
    return false;
  }

  /// 確認できなかったときは直前の結果のまま（初回は使える側）。
  /// 一度ブロックしたあとに圏外にしても抜けられないようにするため。
  Future<void> check() async {
    final source = ref.read(forceUpdateSourceProvider);
    try {
      final minimum = await source.minimumVersion().timeout(_timeout);
      if (minimum == null) return;
      final current = await source.currentVersion();
      if (!ref.mounted) return;
      state = isOlderThan(current, minimum);
    } catch (e) {
      debugPrint('Force update check failed: $e');
    }
  }
}
