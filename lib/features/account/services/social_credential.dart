import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SocialProvider { apple, google }

extension SocialProviderUi on SocialProvider {
  String get label => switch (this) {
    SocialProvider.apple => 'Apple',
    SocialProvider.google => 'Google',
  };

  /// Supabase の `identities[].provider` の値。
  String get identityName => switch (this) {
    SocialProvider.apple => 'apple',
    SocialProvider.google => 'google',
  };
}

/// ネイティブのサインインで得た、Supabase に渡す ID トークン一式。
class SocialCredential {
  const SocialCredential({
    required this.provider,
    required this.idToken,
    this.accessToken,
    this.rawNonce,
    this.displayName,
  });

  final SocialProvider provider;
  final String idToken;
  final String? accessToken;
  final String? rawNonce;

  /// Apple は初回認可時しか氏名を返さないため、取れたときだけ入る。
  final String? displayName;

  OAuthProvider get oauthProvider => switch (provider) {
    SocialProvider.apple => OAuthProvider.apple,
    SocialProvider.google => OAuthProvider.google,
  };
}

/// ユーザーがサインイン画面を閉じた（エラー表示は不要）。
class SocialSignInCancelled implements Exception {
  const SocialSignInCancelled();
}

/// Apple はネイティブ UI がある iOS / macOS のみ提供する。
bool get isAppleSignInSupported =>
    !kIsWeb && (Platform.isIOS || Platform.isMacOS);

/// Google のクライアント ID が `.env` にそろっているか。
/// 未設定のまま Google ボタンを出すと、押しても設定エラーになるだけなので出さない。
bool get isGoogleSignInConfigured {
  if (!dotenv.isInitialized) return false;
  bool has(String key) => (dotenv.env[key] ?? '').trim().isNotEmpty;
  final needsIosClient = !kIsWeb && Platform.isIOS;
  return has('GOOGLE_WEB_CLIENT_ID') &&
      (!needsIosClient || has('GOOGLE_IOS_CLIENT_ID'));
}

/// この端末・設定で使えるログイン方法（表示順）。
List<SocialProvider> get availableSocialProviders => [
  if (isAppleSignInSupported) SocialProvider.apple,
  if (isGoogleSignInConfigured) SocialProvider.google,
];

String _sha256(String input) => sha256.convert(utf8.encode(input)).toString();

Future<SocialCredential> obtainAppleCredential(GoTrueClient auth) async {
  final rawNonce = auth.generateRawNonce();
  try {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: _sha256(rawNonce),
    );
    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple から認証情報を取得できませんでした。');
    }
    final name = [
      credential.familyName,
      credential.givenName,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
    return SocialCredential(
      provider: SocialProvider.apple,
      idToken: idToken,
      rawNonce: rawNonce,
      displayName: name.isEmpty ? null : name,
    );
  } on SignInWithAppleAuthorizationException catch (e) {
    if (e.code == AuthorizationErrorCode.canceled) {
      throw const SocialSignInCancelled();
    }
    debugPrint('Sign in with Apple failed: $e');
    throw UserFacingException(appleSignInErrorMessage(e.code));
  }
}

/// Apple のサインインが失敗したときに見せる文言。
///
/// unknown（エラー 1000）は、端末が Apple アカウントにサインインしていないときや、
/// App ID で Sign In with Apple が有効になっていないときに返る。
String appleSignInErrorMessage(AuthorizationErrorCode code) => switch (code) {
  AuthorizationErrorCode.unknown =>
    'Apple でサインインできませんでした。端末の「設定」で Apple アカウントにサインインしているか確認してください。',
  AuthorizationErrorCode.notHandled || AuthorizationErrorCode.notInteractive =>
    'Apple でのサインインを完了できませんでした。もう一度お試しください。',
  _ => 'Apple でのサインインに失敗しました。しばらくして再度お試しください。',
};

const _googleScopes = ['email', 'profile'];

/// [GoogleSignIn.initialize] はアプリ起動中に 1 回だけ呼べるため、nonce もその単位で固定する。
String? _googleRawNonce;
Future<void>? _googleInit;

Future<void> _ensureGoogleInitialized(GoTrueClient auth) {
  return _googleInit ??= () async {
    final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
    if (webClientId == null || webClientId.isEmpty) {
      throw StateError(
        '.env に GOOGLE_WEB_CLIENT_ID が設定されていません（env.example を参照）',
      );
    }
    final iosClientId = dotenv.env['GOOGLE_IOS_CLIENT_ID'];
    final rawNonce = auth.generateRawNonce();
    await GoogleSignIn.instance.initialize(
      clientId: (iosClientId?.isEmpty ?? true) ? null : iosClientId,
      serverClientId: webClientId,
      nonce: _sha256(rawNonce),
    );
    _googleRawNonce = rawNonce;
  }();
}

Future<SocialCredential> obtainGoogleCredential(GoTrueClient auth) async {
  try {
    await _ensureGoogleInitialized(auth);
  } catch (_) {
    _googleInit = null;
    rethrow;
  }
  try {
    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: _googleScopes,
    );
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google から認証情報を取得できませんでした。');
    }
    final authorization = await account.authorizationClient
        .authorizationForScopes(_googleScopes);
    return SocialCredential(
      provider: SocialProvider.google,
      idToken: idToken,
      accessToken: authorization?.accessToken,
      rawNonce: _googleRawNonce,
      displayName: account.displayName,
    );
  } on GoogleSignInException catch (e) {
    // Google のエラー画面（テストユーザー外など）を閉じた場合も canceled になるので、理由を残す
    debugPrint('Google sign-in ended: ${e.code} ${e.description}');
    if (e.code == GoogleSignInExceptionCode.canceled) {
      throw const SocialSignInCancelled();
    }
    rethrow;
  }
}

Future<void> signOutFromGoogle() async {
  if (_googleInit == null) return;
  try {
    await GoogleSignIn.instance.signOut();
  } catch (_) {}
}
