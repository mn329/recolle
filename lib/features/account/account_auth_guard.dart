import 'package:flutter/material.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/features/account/services/social_credential.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef SetBusy = void Function(bool value);

Future<void> runAccountAuthGuarded({
  required BuildContext context,
  required bool Function() isBusy,
  required SetBusy setBusy,
  required Future<void> Function() fn,
}) async {
  if (isBusy()) return;
  setBusy(true);
  try {
    await fn();
  } on SocialSignInCancelled {
    // ユーザー自身が閉じただけなので何も表示しない。
  } on AuthException catch (e) {
    debugPrint(
      'AuthException code=${e.code} statusCode=${e.statusCode} message=${e.message}',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(toUserFriendlyMessage(e))));
  } catch (e) {
    debugPrint('Account action failed: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(toUserFriendlyMessage(e))));
  } finally {
    if (context.mounted) {
      setBusy(false);
    }
  }
}
