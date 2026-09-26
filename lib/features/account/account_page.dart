import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/auth/auth_reauth_in_progress.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/features/account/account_auth_guard.dart';
import 'package:recolle/features/account/providers/auth_providers.dart';
import 'package:recolle/features/account/providers/auth_service_provider.dart';
import 'package:recolle/features/account/services/auth_service.dart';
import 'package:recolle/features/account/services/social_credential.dart';
import 'package:recolle/features/account/widgets/account_expandable_section.dart';
import 'package:recolle/features/account/widgets/account_profile_card.dart';
import 'package:recolle/features/account/widgets/account_signed_in_panel.dart';
import 'package:recolle/features/account/widgets/social_sign_in_buttons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountPage extends HookConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authUserProvider);
    final authService = ref.read(authServiceProvider);
    final isBusy = useState(false);

    Future<void> runGuarded(Future<void> Function() fn) async {
      await runAccountAuthGuarded(
        context: context,
        isBusy: () => isBusy.value,
        setBusy: (v) => isBusy.value = v,
        fn: fn,
      );
    }

    void continueWith(SocialProvider provider) {
      runGuarded(() async {
        final messenger = ScaffoldMessenger.of(context);
        final wasAnonymous = authService.currentUser?.isAnonymous ?? false;
        try {
          await authService.continueWith(provider);
        } on SocialIdentityInUseException catch (e) {
          if (!context.mounted) return;
          final ok = await showConfirmDialog(
            context,
            title: '${provider.label} アカウントは登録済みです',
            message: wasAnonymous
                ? 'この ${provider.label} アカウントで以前登録した記録に切り替えます。'
                    'この端末で未登録のまま作った記録は引き継がれません。'
                : 'この ${provider.label} アカウントに切り替えます。',
            okText: '切り替える',
            cancelText: 'キャンセル',
          );
          if (!ok) return;
          await authService.switchToExistingAccount(e.credential);
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              wasAnonymous
                  ? '${provider.label} と連携しました。機種変更しても記録を引き継げます'
                  : '${provider.label} でログインしました',
            ),
          ),
        );
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Account')),
      body: authUser.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              toUserFriendlyMessage(e),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
        data: (user) {
          return ListenableBuilder(
            listenable: AuthReauthInProgress.instance,
            builder: (context, child) {
              // signOut 直後〜 signInAnonymously 完了まで一瞬 [user] が null になる。
              // その区間を「未接続」と出すと、ログアウト操作直後に謎の画面になる。
              if (user == null && AuthReauthInProgress.instance.isInProgress) {
                return const Center(child: CircularProgressIndicator());
              }

              final isAnonymous = user?.isAnonymous ?? false;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AccountProfileCard(
                    title: _profileTitle(user),
                    subtitle: user == null
                        ? '接続し直すか、Apple / Google でログインしてください'
                        : (isAnonymous ? 'この端末だけに保存されています' : '登録済み'),
                  ),
                  const SizedBox(height: 16),
                  if (user == null || isAnonymous)
                    _GuestPanel(
                      showConnectionRecovery: user == null,
                      isBusy: isBusy.value,
                      runGuarded: runGuarded,
                      authService: authService,
                      onContinueWith: continueWith,
                    )
                  else
                    AccountSignedInPanel(
                      isBusy: isBusy.value,
                      runGuarded: runGuarded,
                      authService: authService,
                      onLink: continueWith,
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static String _profileTitle(User? user) {
    if (user == null) return '未接続';
    if (user.isAnonymous) return '未登録';
    final name = user.userMetadata?['display_name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    final email = user.email;
    return (email != null && email.isNotEmpty) ? email : 'アカウント';
  }
}

/// 未接続・匿名ユーザー向け：Apple / Google での引き継ぎを主導線にする。
class _GuestPanel extends StatelessWidget {
  const _GuestPanel({
    required this.showConnectionRecovery,
    required this.isBusy,
    required this.runGuarded,
    required this.authService,
    required this.onContinueWith,
  });

  final bool showConnectionRecovery;
  final bool isBusy;
  final Future<void> Function(Future<void> Function() fn) runGuarded;
  final AuthService authService;
  final void Function(SocialProvider provider) onContinueWith;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showConnectionRecovery) ...[
          AccountExpandableSection(
            title: '接続',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Supabase への接続に失敗したか、前回のセッションが切れています。',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary.withAlpha(200),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: isBusy
                      ? null
                      : () => runGuarded(() async {
                            await authService.signInAnonymously();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('接続しました。思い出の記録を始められます。'),
                              ),
                            );
                          }),
                  child: const Text('登録せずに使う'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        AccountExpandableSection(
          title: showConnectionRecovery ? 'ログイン' : '記録を引き継げるようにする',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                showConnectionRecovery
                    ? '以前 Apple / Google で登録した方は、同じアカウントで記録を復元できます。'
                    : 'いまの記録はこの端末にだけ紐づいています。Apple または Google と連携すると、機種変更しても引き継げます。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary.withAlpha(210),
                ),
              ),
              const SizedBox(height: 16),
              SocialSignInButtons(isBusy: isBusy, onPressed: onContinueWith),
              const SizedBox(height: 12),
              Text(
                '以前メールアドレスで登録した方は、同じメールアドレスの Google アカウントでログインすると記録を引き継げます。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.textSecondary.withAlpha(170),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
