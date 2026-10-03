import 'package:flutter/foundation.dart';
import 'package:recolle/core/auth/auth_reauth_in_progress.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/records/data/records_local_cache.dart';
import 'package:recolle/features/account/services/social_credential.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Apple / Google アカウントが既に別ユーザーに連携済みで、今のユーザーへは連携できない。
///
/// [switchToExistingAccount] に [credential] を渡すとそのアカウントへ切り替えられる。
class SocialIdentityInUseException implements Exception {
  const SocialIdentityInUseException(this.credential);

  final SocialCredential credential;
}

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;

  /// 連携済みの Apple / Google を表す provider 名。
  Set<String> get linkedProviders => {
    for (final identity in currentUser?.identities ?? const <UserIdentity>[])
      identity.provider,
  };

  Future<void> updateDisplayName(String displayName) async {
    final trimmed = displayName.trim();
    await _client.auth.updateUser(
      UserAttributes(data: <String, dynamic>{'display_name': trimmed}),
    );
  }

  /// Apple / Google で続行する。
  ///
  /// - セッションあり（匿名・連携済みユーザー）: 今のユーザーに連携し、記録を引き継ぐ
  /// - セッションなし: そのアカウントでサインイン（未登録なら新規作成）
  ///
  /// 連携先が既に別ユーザーで使われていると [SocialIdentityInUseException]、
  /// サインイン画面を閉じたときは [SocialSignInCancelled] を投げる。
  Future<void> continueWith(SocialProvider provider) async {
    final credential = await _obtainCredential(provider);
    if (currentUser == null) {
      await _signInWithCredential(credential);
    } else {
      try {
        await _client.auth.linkIdentityWithIdToken(
          provider: credential.oauthProvider,
          idToken: credential.idToken,
          accessToken: credential.accessToken,
          nonce: credential.rawNonce,
        );
      } on AuthException catch (e) {
        // email_exists: 同じメールアドレスの別ユーザーがいる。そちらでサインインすれば
        // Supabase がメールアドレスで自動リンクするので、切り替えで入れる
        if (e.code == 'identity_already_exists' || e.code == 'email_exists') {
          throw SocialIdentityInUseException(credential);
        }
        rethrow;
      }
    }
    await _applyDisplayNameIfMissing(credential.displayName);
  }

  /// [SocialIdentityInUseException] のアカウントへ切り替える。
  /// 今の匿名ユーザーの記録は切り替え先に移らない。
  Future<void> switchToExistingAccount(SocialCredential credential) async {
    final previousUserId = currentUser?.id;
    AuthReauthInProgress.instance.begin();
    try {
      await _signInWithCredential(credential);
      // 切り替え前の（匿名の）ユーザーの記録は、もう開けないので端末から消す
      if (previousUserId != null && previousUserId != currentUser?.id) {
        await _clearLocalCaches(previousUserId);
      }
    } finally {
      AuthReauthInProgress.instance.end();
    }
  }

  /// Supabase 側で Anonymous Sign-ins が有効である必要があります。
  Future<void> signInAnonymously() async {
    await _client.auth.signInAnonymously();
  }

  /// セッション更新（期限切れ対策）。
  Future<void> refreshSession() async {
    await _client.auth.refreshSession();
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    await signOutFromGoogle();
  }

  /// 現在のセッションを破棄して、匿名セッションに戻します。
  /// このアプリは「ユーザーID単位」でrecordsを見ているため、IDが変わる点に注意。
  Future<void> resetToAnonymous() async {
    final previousUserId = currentUser?.id;
    AuthReauthInProgress.instance.begin();
    try {
      await signOut();
      await _client.auth.signInAnonymously();
      if (previousUserId != null) await _clearLocalCaches(previousUserId);
    } finally {
      AuthReauthInProgress.instance.end();
    }
  }

  /// 登録済みユーザーをアプリ上から完全削除（Edge Function `delete-account`）。
  /// 成功後、匿名利用に戻る。
  Future<void> deleteRegisteredAccount() async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException('セッションがありません。');
    }
    if (user.isAnonymous) {
      throw const AuthException('登録済みのアカウントのみ削除できます。');
    }

    // 期限切れのトークンで呼ぶと「再ログインしてから」のような失敗になるので、先に更新しておく。
    // 更新できなくても、サーバーが受け付ければ削除は進められる
    try {
      await _client.auth.refreshSession();
    } catch (_) {}

    try {
      await _invokeDeleteAccount();
    } on FunctionException catch (e) {
      if (e.status != 401) throw AuthException(_deleteErrorMessage(e));
      // 401 は期限切れなど。セッションを更新してもう一度だけ試す
      try {
        await _client.auth.refreshSession();
        await _invokeDeleteAccount();
      } on FunctionException catch (e) {
        throw AuthException(_deleteErrorMessage(e));
      } on AuthException {
        throw const AuthException('アカウントの削除に失敗しました。もう一度お試しください。');
      }
    }

    await _clearLocalCaches(user.id);
    AuthReauthInProgress.instance.begin();
    try {
      try {
        await signOut();
      } catch (_) {}
      try {
        await _client.auth.signInAnonymously();
      } catch (e) {
        throw AuthException('削除後の再接続に失敗しました: $e');
      }
    } finally {
      AuthReauthInProgress.instance.end();
    }
  }

  /// ログアウト・アカウント削除のあと、そのユーザーの記録とお気に入りを端末に残さない。
  /// 消せなくても本来の操作は成功として扱う。
  static Future<void> _clearLocalCaches(String userId) async {
    try {
      await RecordsLocalCache.clear(userId);
      await favoriteArtistsCacheFile.delete(userId);
    } catch (e) {
      debugPrint('Local cache cleanup failed: $e');
    }
  }

  Future<void> _invokeDeleteAccount() async {
    await _client.functions.invoke('delete-account');
  }

  static String _deleteErrorMessage(FunctionException e) {
    const fallback = 'アカウントの削除に失敗しました。もう一度お試しください。';
    final details = e.details;
    if (details is Map) {
      final err = details['error'] ?? details['message'];
      final text = err?.toString() ?? '';
      // サーバーの英語メッセージ（Invalid JWT など）はそのまま見せない
      return RegExp(r'[\u3040-\u30ff\u4e00-\u9faf]').hasMatch(text)
          ? text
          : fallback;
    }
    return fallback;
  }

  Future<SocialCredential> _obtainCredential(SocialProvider provider) {
    return switch (provider) {
      SocialProvider.apple => obtainAppleCredential(_client.auth),
      SocialProvider.google => obtainGoogleCredential(_client.auth),
    };
  }

  Future<void> _signInWithCredential(SocialCredential credential) async {
    await _client.auth.signInWithIdToken(
      provider: credential.oauthProvider,
      idToken: credential.idToken,
      accessToken: credential.accessToken,
      nonce: credential.rawNonce,
    );
  }

  Future<void> _applyDisplayNameIfMissing(String? name) async {
    if (name == null || name.trim().isEmpty) return;
    final current = currentUser?.userMetadata?['display_name'];
    if (current is String && current.trim().isNotEmpty) return;
    try {
      await updateDisplayName(name);
    } catch (_) {
      // 表示名はあとから変更できるため、連携自体は成功扱いにする。
    }
  }
}
