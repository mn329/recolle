import 'package:flutter/material.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/features/account/services/auth_service.dart';
import 'package:recolle/features/account/services/social_credential.dart';
import 'package:recolle/features/account/widgets/account_expandable_section.dart';
import 'package:recolle/features/account/widgets/social_sign_in_buttons.dart';

class AccountSignedInPanel extends StatelessWidget {
  const AccountSignedInPanel({
    super.key,
    required this.isBusy,
    required this.runGuarded,
    required this.authService,
    required this.onLink,
  });

  final bool isBusy;
  final Future<void> Function(Future<void> Function() fn) runGuarded;
  final AuthService authService;
  final void Function(SocialProvider provider) onLink;

  @override
  Widget build(BuildContext context) {
    final linked = authService.linkedProviders;
    final linkedSocial = {
      for (final p in SocialProvider.values)
        if (linked.contains(p.identityName)) p,
    };
    final canLinkMore = SocialProvider.values.any(
      (p) =>
          !linkedSocial.contains(p) &&
          (p != SocialProvider.apple || isAppleSignInSupported),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountExpandableSection(
          title: 'ログイン方法',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in linkedSocial)
                _LinkedRow(label: '${p.label} で連携済み'),
              if (linkedSocial.isEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Apple または Google を連携しておくと、機種変更後もログインできます。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.textSecondary.withAlpha(200),
                  ),
                ),
              ],
              if (canLinkMore) ...[
                const SizedBox(height: 12),
                SocialSignInButtons(
                  isBusy: isBusy,
                  hiddenProviders: linkedSocial,
                  onPressed: onLink,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        AccountExpandableSection(
          title: 'ログアウト',
          child: FilledButton.tonal(
            onPressed: isBusy
                ? null
                : () {
                    runGuarded(() async {
                      // await 後はこのパネルはツリーから外れ context が unmount しうる。
                      // Messenger は先に取っておけば表示できる。
                      final messenger = ScaffoldMessenger.of(context);
                      await authService.resetToAnonymous();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('ログアウトしました。')),
                      );
                    });
                  },
            child: const Text('ログアウト'),
          ),
        ),
        const SizedBox(height: 16),
        AccountExpandableSection(
          title: 'アカウントを削除',
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.withAlpha(38),
            ),
            onPressed: isBusy
                ? null
                : () {
                    runGuarded(() async {
                      final messenger = ScaffoldMessenger.of(context);
                      final ok = await showConfirmDialog(
                        context,
                        title: '本当に削除しますか？',
                        message: '思い出データと登録アカウントを完全に消去します。再度登録しても同じ内容は戻りません。',
                        okText: '完全に削除',
                        cancelText: 'キャンセル',
                      );
                      if (!ok) return;
                      await authService.deleteRegisteredAccount();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('アカウントとデータを削除しました')),
                      );
                    });
                  },
            child: const Text('アカウントを完全に削除'),
          ),
        ),
      ],
    );
  }
}

class _LinkedRow extends StatelessWidget {
  const _LinkedRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: AppColors.gold),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
