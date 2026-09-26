import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:recolle/core/auth/auth_reauth_in_progress.dart';
import 'package:recolle/features/records/screens/home_screen.dart';
import 'package:recolle/components/scaffold_with_navbar.dart';
import 'package:recolle/features/account/account_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ナビゲーションの状態を管理するためのキー
// ダイアログ表示などを制御する際に必要になります
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final _accountNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'account');

class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final _authRefresh = _GoRouterRefreshStream(
  Supabase.instance.client.auth.onAuthStateChange,
);

/// 認証イベント・匿名再ログイン中のいずれかで [GoRouter] を再評価する。
final _goRouterListenable = Listenable.merge([
  _authRefresh,
  AuthReauthInProgress.instance,
]);

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  refreshListenable: _goRouterListenable,
  redirect: (context, state) {
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    final loc = state.matchedLocation;

    // ログアウト→匿名サインインの一瞬、セッションは null になる。そこで /account
    // へ飛ばすと未接続UIがチラつくので、その間は遷移しない。
    if (!loggedIn && AuthReauthInProgress.instance.isInProgress) {
      return null;
    }

    // 未セッション時はタブ内のアカウントで再接続できるようにする
    if (!loggedIn) {
      return loc == '/account' ? null : '/account';
    }
    return null;
  },
  routes: [
    // 旧バージョンの /login、メール再設定系のディープリンクを /account へ
    for (final legacyPath in ['/login', '/forgot-password', '/reset-password'])
      GoRoute(path: legacyPath, redirect: (context, state) => '/account'),
    // StatefulShellRoute: タブ切り替え時に各画面の状態（スクロール位置など）を保持するためのルート
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        // ナビゲーションバーを含む共通の枠組み（Scaffold）を返します
        // navigationShellは現在表示すべき画面やタブの制御情報を持ちます
        return ScaffoldWithNavBar(navigationShell: navigationShell);
      },
      branches: [
        // 1つ目のタブ：ホーム画面
        StatefulShellBranch(
          navigatorKey: _homeNavigatorKey,
          routes: [
            GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          ],
        ),
        // 2つ目のタブ：アカウント画面
        StatefulShellBranch(
          navigatorKey: _accountNavigatorKey,
          routes: [
            GoRoute(
              path: '/account',
              builder: (context, state) => const AccountPage(),
            ),
          ],
        ),
      ],
    ),
  ],
);
