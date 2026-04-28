import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:recolle/core/auth/auth_reauth_in_progress.dart';
import 'package:recolle/core/auth/email_auth_deep_link.dart';
import 'package:recolle/core/auth/password_recovery_nav_flag.dart';
import 'package:recolle/core/auth/recovery_session.dart';
import 'package:recolle/features/account/screens/forgot_password_screen.dart';
import 'package:recolle/features/account/screens/reset_password_screen.dart';
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

/// 認証イベント・匿名再ログイン中・再設定誘導フラグのいずれかで [GoRouter] を再評価する。
final _goRouterListenable = Listenable.merge([
  _authRefresh,
  AuthReauthInProgress.instance,
  PasswordRecoveryNavFlag.instance,
]);

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  refreshListenable: _goRouterListenable,
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final loggedIn = session != null;
    final loc = state.matchedLocation;

    // ログアウト→匿名サインインの一瞬、セッションは null になる。そこで /account
    // へ飛ばすと未接続UIがチラつくので、その間は遷移しない。
    if (!loggedIn && AuthReauthInProgress.instance.isInProgress) {
      return null;
    }

    // メールのパスワードリカバリーリンク後は、新パスワード入力画面へ誘導する。
    if (loggedIn &&
        !session.user.isAnonymous &&
        sessionRequiresNewPasswordAfterRecovery(session) &&
        loc != '/reset-password') {
      return '/reset-password';
    }

    if (loc == '/reset-password') {
      if (!loggedIn ||
          session.user.isAnonymous ||
          !sessionRequiresNewPasswordAfterRecovery(session)) {
        return '/account';
      }
      return null;
    }

    // リカバリーリンク直後は「メール送信」ではなく新パスワード入力へ。
    // ログイン済みでも /forgot-password は利用可（審査・利用者が再設定メールを送るため）。
    if (loc == '/forgot-password' &&
        loggedIn &&
        !session.user.isAnonymous &&
        sessionRequiresNewPasswordAfterRecovery(session)) {
      return '/reset-password';
    }

    // 未セッション時はタブ内のアカウントで再接続可能にする（メール必須の導線にしない）
    if (!loggedIn) {
      if (loc == '/account') {
        return null;
      }
      if (loc == '/login') {
        return '/account';
      }
      if (loc == '/forgot-password') {
        return null;
      }
      return '/account';
    }

    if (loc == '/login') {
      return '/';
    }
    return null;
  },
  routes: [
    // 旧バージョンの /login ディープリンクを /account へ
    GoRoute(
      path: '/login',
      redirect: (context, state) => '/account',
    ),
    GoRoute(
      path: '/forgot-password',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final email = state.uri.queryParameters['email'] ?? '';
        return ForgotPasswordScreen(initialEmail: email);
      },
    ),
    GoRoute(
      path: '/reset-password',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ResetPasswordScreen(),
    ),
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

StreamSubscription<Uri>? _emailAuthLinkSubscription;
StreamSubscription<AuthState>? _emailAuthStateSubscription;

/// メール内の認証リンク（カスタムスキーム）でアプリが開いたあと、
/// **メールアドレス確認が済んだ非匿名セッション**になったらホーム（`/`）へ寄せる。
/// パスワード再設定フロー中は [sessionRequiresNewPasswordAfterRecovery] に従い `/reset-password`。
///
/// [scheduleHomeAfterColdStartEmailLink]: `main` で既に `getSessionFromUrl` 済みのとき、
/// ここでは `signedIn` が飛ばないことがあるため初回フレーム後にホーム遷移を予約する。
void attachEmailLinkAccountNavigation({
  bool scheduleHomeAfterColdStartEmailLink = false,
}) {
  _emailAuthLinkSubscription?.cancel();
  _emailAuthStateSubscription?.cancel();

  var pendingAuthDeepLink = false;

  /// メールリンク後の遷移。セッションがメールユーザーに切り替わってからホームへ向ける。
  Future<void> goPostEmailAuthDestinationAsync() async {
    await Future<void>.delayed(Duration.zero);
    var s = Supabase.instance.client.auth.currentSession;
    if (s == null || s.user.isAnonymous) return;

    if (sessionRequiresNewPasswordAfterRecovery(s)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = router.routerDelegate.navigatorKey.currentState;
        if (nav == null || !nav.mounted) return;
        router.go('/reset-password');
      });
      return;
    }

    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (_) {}

    s = Supabase.instance.client.auth.currentSession;
    if (s == null || s.user.isAnonymous) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = router.routerDelegate.navigatorKey.currentState;
      if (nav == null || !nav.mounted) return;
      final latest = Supabase.instance.client.auth.currentSession;
      if (latest == null || latest.user.isAnonymous) return;
      router.go('/');
    });
  }

  void goPostEmailAuthDestination() {
    unawaited(goPostEmailAuthDestinationAsync());
  }

  Future<void> handleEmailAuthCallbackUri(Uri uri) async {
    await exchangeSessionFromEmailAuthDeepLink(uri);
    final s = Supabase.instance.client.auth.currentSession;
    if (s != null && !s.user.isAnonymous) {
      pendingAuthDeepLink = false;
      goPostEmailAuthDestination();
    } else {
      pendingAuthDeepLink = false;
    }
  }

  void onAuthCallbackUri(Uri? uri) {
    if (!isEmailAuthCallbackDeepLink(uri)) return;
    pendingAuthDeepLink = true;
    // 交換完了まで待つ（冷起動は main.dart の getInitialLink で先に処理済みのため、
    // ここで再度 getInitialLink すると PKCE code の二重消費になりやすい）。
    unawaited(handleEmailAuthCallbackUri(uri!));
  }

  _emailAuthLinkSubscription =
      AppLinks().uriLinkStream.listen(onAuthCallbackUri);

  Session? previousSession = Supabase.instance.client.auth.currentSession;
  _emailAuthStateSubscription =
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    final session = data.session;
    try {
      if (data.event == AuthChangeEvent.signedOut) {
        PasswordRecoveryNavFlag.instance.clear();
      }
      if (data.event == AuthChangeEvent.passwordRecovery &&
          session != null &&
          !session.user.isAnonymous) {
        PasswordRecoveryNavFlag.instance.setActiveFromAuthEvent();
        pendingAuthDeepLink = false;
        goPostEmailAuthDestination();
        return;
      }
      // PKCE やメール確認のタイミングで signedIn 以外（tokenRefreshed / userUpdated）だけ
      // 来ることがあるため、リンク経路または匿名→本登録の遷移ならまとめてホームへ誘導する。
      if (session != null &&
          !session.user.isAnonymous &&
          !sessionRequiresNewPasswordAfterRecovery(session)) {
        final wasAnonymous = previousSession?.user.isAnonymous ?? false;
        final fromEmailDeepLink = pendingAuthDeepLink;
        if (fromEmailDeepLink || wasAnonymous) {
          switch (data.event) {
            case AuthChangeEvent.signedIn:
            case AuthChangeEvent.tokenRefreshed:
            case AuthChangeEvent.userUpdated:
              pendingAuthDeepLink = false;
              goPostEmailAuthDestination();
            default:
              break;
          }
        }
      }
    } finally {
      previousSession = session;
    }
  });

  if (scheduleHomeAfterColdStartEmailLink) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      goPostEmailAuthDestination();
    });
  }
}
