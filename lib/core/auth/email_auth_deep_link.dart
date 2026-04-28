import 'package:flutter/foundation.dart';
import 'package:recolle/core/auth/auth_reauth_in_progress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// メール内の認証コールバック URL か（`auth_redirect.dart` と一致するスキーム）。
bool isEmailAuthCallbackDeepLink(Uri? uri) {
  if (uri == null) return false;
  if (uri.scheme != 'io.supabase.recolle' || uri.host != 'login-callback') {
    return false;
  }
  final f = uri.fragment;
  if (f.contains('error_description')) return false;
  return f.contains('access_token') ||
      f.contains('code') ||
      uri.queryParameters.containsKey('code');
}

/// `#code=...` は [Uri.queryParameters] に載らない。PKCE の `getSessionFromUrl` が読めるよう query に繋ぐ。
Uri normalizeEmailAuthDeepLink(Uri uri) {
  if (uri.fragment.isEmpty) return uri;
  final fragParams = Uri.splitQueryString(uri.fragment);
  if (fragParams.isEmpty) return uri;
  final merged = Map<String, String>.from(uri.queryParameters);
  merged.addAll(fragParams);
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    queryParameters: merged.isEmpty ? null : merged,
  );
}

/// メール確認コールバック URL からセッションを確立する。
///
/// `getSessionFromUrl` は PKCE 時に **query の `code` のみ**を見る実装のため、
/// `#code=...` は [normalizeEmailAuthDeepLink] で query に載せてから渡す。
/// メール確認で `#access_token=...&refresh_token=...`（implicit 形式）だけが返る場合は
/// PKCE 分岐で失敗するため `setSession(refresh_token)` で確立する。
Future<void> establishSessionFromNormalizedEmailCallbackUri(
  Uri normalized,
) async {
  final client = Supabase.instance.client;
  final q = normalized.queryParameters;

  if (q.containsKey('code') && q['code']!.isNotEmpty) {
    await client.auth.getSessionFromUrl(normalized);
    return;
  }

  final refresh = q['refresh_token'];
  if (refresh != null &&
      refresh.isNotEmpty &&
      (q['access_token'] ?? '').isNotEmpty) {
    await client.auth.setSession(refresh);
    return;
  }

  await client.auth.getSessionFromUrl(normalized);
}

/// メールリンクからセッションを確立する。冷起動・バックグラウンド復帰の両方で呼べる。
/// 二重呼び出しで PKCE の code が無効になるのを防ぐため、同時に1本だけ実行する。
Future<void>? _emailAuthExchangeSerial;

/// 同一 URL の再交換（`getInitialLink` と `uriLinkStream` の二重など）を避ける。
String? _successfulEmailAuthExchangeKey;

Future<void> exchangeSessionFromEmailAuthDeepLink(Uri uri) async {
  while (_emailAuthExchangeSerial != null) {
    await _emailAuthExchangeSerial;
  }
  final done = _exchangeSessionFromEmailAuthDeepLinkImpl(uri);
  _emailAuthExchangeSerial = done;
  try {
    await done;
  } finally {
    if (identical(_emailAuthExchangeSerial, done)) {
      _emailAuthExchangeSerial = null;
    }
  }
}

Future<void> _exchangeSessionFromEmailAuthDeepLinkImpl(Uri uri) async {
  final normalized = normalizeEmailAuthDeepLink(uri);
  final client = Supabase.instance.client;
  final exchangeKey = normalized.toString();
  final existing = client.auth.currentSession;
  if (_successfulEmailAuthExchangeKey == exchangeKey &&
      existing != null &&
      !existing.user.isAnonymous) {
    return;
  }

  AuthReauthInProgress.instance.begin();
  try {
    final current = client.auth.currentSession;
    if (current != null && current.user.isAnonymous) {
      // 匿名セッションが残っていると、メール認証後も匿名のまま見えることがあるため、
      // callback の code 交換前にローカルセッションだけ破棄して切り替えを明確にする。
      await client.auth.signOut(scope: SignOutScope.local);
    }
    await establishSessionFromNormalizedEmailCallbackUri(normalized);
  } catch (e, st) {
    assert(() {
      debugPrint(
        'exchangeSessionFromEmailAuthDeepLink (二重や期限切れでは無視可): $e\n$st',
      );
      return true;
    }());
  } finally {
    AuthReauthInProgress.instance.end();
  }

  final after = client.auth.currentSession;
  if (after != null && !after.user.isAnonymous) {
    _successfulEmailAuthExchangeKey = exchangeKey;
  }

  // signOut(local) 後に交換だけ失敗した場合など、セッション無しで止まらないようにする。
  if (client.auth.currentSession == null) {
    try {
      await client.auth.signInAnonymously();
    } catch (e, st) {
      assert(() {
        debugPrint(
          'exchangeSessionFromEmailAuthDeepLink: anonymous recovery failed: $e\n$st',
        );
        return true;
      }());
    }
  }
}
