import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/core/auth/auth_reauth_in_progress.dart';
import 'package:recolle/core/demo/demo_mode.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/router/router.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/core/widgets/app_root_builder.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:recolle/features/records/home_widget_sync.dart';
import 'package:recolle/features/records/providers/records_provider.dart';

/// App Store: 未登録でも使えるよう、起動直後に匿名セッションを保証する。
/// Supabase ダッシュボードで「Anonymous sign-ins」が有効なこと。
Future<void> _ensureAnonymousSession() async {
  final client = Supabase.instance.client;
  if (client.auth.currentSession != null) {
    return;
  }
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      // runApp の前に待つので、応答がない回線でスプラッシュ画面のまま止まらないよう区切る
      await client.auth.signInAnonymously().timeout(const Duration(seconds: 6));
      return;
    } catch (e, st) {
      assert(() {
        debugPrint('Anonymous sign-in failed: $e\n$st');
        return true;
      }());
      if (attempt < 1) {
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
  }
}

String _requireEnv(String key) {
  final value = dotenv.env[key];
  if (value == null || value.isEmpty) {
    throw StateError('.env に $key が設定されていません（env.example を参照）');
  }
  return value;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .envファイルをロード
  await dotenv.load(fileName: ".env");

  // Supabaseの初期化

  await Supabase.initialize(
    url: _requireEnv('SUPABASE_URL'),
    // supabase_flutter 2.x は publishable キーも anonKey 引数で受け取る。
    anonKey: _requireEnv('SUPABASE_PUBLISHABLE_KEY'),
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      // ログインは ID トークン方式のみで、URL 経由のセッション受け取りは使わない。
      detectSessionInUri: false,
    ),
  );

  // セッションがない場合は匿名サインインを試みる
  await _ensureAnonymousSession();

  // 1. ProviderScope: Riverpodの状態管理をアプリ全体で使えるようにする
  runApp(
    ProviderScope(
      // スクリーンショット撮影用。--dart-define=DEMO_MODE=true のときだけデモデータを出す
      overrides: kDemoMode ? demoOverrides() : const [],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 圏外で起動して匿名サインインできなかったときは、つながったところでやり直す
    ref.listen(connectivityProvider, (_, next) {
      final results = next.asData?.value;
      if (results == null || !isConnectivityOnline(results)) return;
      final client = Supabase.instance.client;
      if (client.auth.currentSession != null ||
          AuthReauthInProgress.instance.isInProgress) {
        return;
      }
      unawaited(() async {
        try {
          await client.auth.signInAnonymously();
        } catch (e) {
          debugPrint('Anonymous sign-in retry failed: $e');
        }
      }());
    });

    ref.listen(recordsProvider, (_, next) {
      final records = next.asData?.value;
      if (records != null) syncHomeWidget(records);
    });

    // 2. MaterialApp.router: GoRouterを使ったナビゲーション機能付きのアプリ定義
    return MaterialApp.router(
      title: 'recolle',
      debugShowCheckedModeBanner: false,
      // 3. テーマ設定: AppTheme で定義したライト・ダークのテーマを適用
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      // 端末の外観設定（ライト・ダーク）に合わせる
      themeMode: ThemeMode.system,

      // 4. ルーティング設定: router.dart で定義した画面遷移ルールを適用
      routerConfig: router,
      builder: buildAppRoot,

      // 5. 日本語化設定: カレンダーや戻るボタンなどの標準UIを日本語にする
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja', 'JP')],
    );
  }
}
