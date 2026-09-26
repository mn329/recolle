import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/auth/auth_reauth_in_progress.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/app_toast.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/account/account_auth_guard.dart';
import 'package:recolle/features/account/providers/auth_providers.dart';
import 'package:recolle/features/account/providers/auth_service_provider.dart';
import 'package:recolle/features/account/services/auth_service.dart';
import 'package:recolle/features/account/services/social_credential.dart';
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
          );
          if (!ok) return;
          await authService.switchToExistingAccount(e.credential);
        }
        AppToast.show(
          wasAnonymous
              ? '${provider.label} と連携しました。機種変更しても記録を引き継げます'
              : '${provider.label} でログインしました',
          icon: CupertinoIcons.checkmark_circle_fill,
        );
      });
    }

    List<Widget> buildSlivers(User? user) {
      final isAnonymous = user?.isAnonymous ?? false;
      return [
        SliverToBoxAdapter(
          child: AccountProfileCard(
            title: _profileTitle(user),
            subtitle: user == null
                ? '接続し直すか、Apple / Google でログインしてください'
                : (isAnonymous ? 'この端末だけに保存されています' : '登録済み'),
            isRegistered: user != null && !isAnonymous,
          ),
        ),
        SliverToBoxAdapter(
          child: user == null || isAnonymous
              ? _GuestPanel(
                  showConnectionRecovery: user == null,
                  isBusy: isBusy.value,
                  runGuarded: runGuarded,
                  authService: authService,
                  onContinueWith: continueWith,
                )
              : AccountSignedInPanel(
                  isBusy: isBusy.value,
                  runGuarded: runGuarded,
                  authService: authService,
                  onLink: continueWith,
                ),
        ),
      ];
    }

    const loading = [
      SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CupertinoActivityIndicator(radius: 14)),
      ),
    ];

    return Scaffold(
      backgroundColor: context.colors.background,
      body: ListenableBuilder(
        listenable: AuthReauthInProgress.instance,
        builder: (context, _) => LargeTitleScrollView(
          title: 'アカウント',
          enTitle: 'ACCOUNT',
          trailing: isBusy.value
              ? const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: CupertinoActivityIndicator(),
                )
              : null,
          slivers: authUser.when(
            loading: () => loading,
            error: (e, _) => [
              SliverFillRemaining(
                hasScrollBody: false,
                child: IosEmptyState(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  message: toUserFriendlyMessage(e),
                ),
              ),
            ],
            // signOut 直後〜 signInAnonymously 完了まで一瞬 user が null になる。
            // その区間を「未接続」と出すと、ログアウト操作直後に謎の画面になる。
            data: (user) =>
                user == null && AuthReauthInProgress.instance.isInProgress
                ? loading
                : buildSlivers(user),
          ),
        ),
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
        if (showConnectionRecovery)
          InsetGroupedSection(
            header: '接続',
            footer: 'Supabase への接続に失敗したか、前回のセッションが切れています。',
            children: [
              GroupedRow(
                leading: const RowIcon(
                  CupertinoIcons.cloud,
                  color: Color(0xFF0A84FF),
                ),
                title: '登録せずに使う',
                onTap: isBusy
                    ? null
                    : () => runGuarded(() async {
                        await authService.signInAnonymously();
                        AppToast.show(
                          '接続しました。思い出の記録を始められます。',
                          icon: CupertinoIcons.checkmark_circle_fill,
                        );
                      }),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 8),
          child: Text(
            showConnectionRecovery ? 'ログイン' : '記録を引き継げるようにする',
            style: sectionHeaderTextStyle(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SocialSignInButtons(isBusy: isBusy, onPressed: onContinueWith),
        ),
      ],
    );
  }
}
