import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/widgets/app_toast.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/account/services/auth_service.dart';
import 'package:recolle/features/account/services/social_credential.dart';
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

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showActionSheet<bool>(
      context,
      message: 'ログアウトすると、この端末では未登録の状態に戻ります。記録は Apple / Google で再ログインすると戻せます。',
      actions: const [
        SheetAction(label: 'ログアウト', value: true, isDestructive: true),
      ],
    );
    if (ok != true) return;
    await runGuarded(() async {
      await authService.resetToAnonymous();
      AppToast.show('ログアウトしました', icon: CupertinoIcons.checkmark_circle_fill);
    });
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: '本当に削除しますか？',
      message: '思い出データと登録アカウントを完全に消去します。再度登録しても同じ内容は戻りません。',
      okText: '完全に削除',
      isDestructive: true,
    );
    if (!ok) return;
    await runGuarded(() async {
      await authService.deleteRegisteredAccount();
      AppToast.show('アカウントとデータを削除しました', icon: CupertinoIcons.trash);
    });
  }

  @override
  Widget build(BuildContext context) {
    final linked = authService.linkedProviders;
    final providers = availableSocialProviders;
    final linkedSocial = {
      for (final p in SocialProvider.values)
        if (linked.contains(p.identityName)) p,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsetGroupedSection(
          header: 'ログイン方法',
          footer: linkedSocial.isEmpty
              ? 'Apple または Google を連携しておくと、機種変更後もログインできます。'
              : '連携したアカウントで、別の端末からも同じ記録にログインできます。',
          children: [
            for (final p in providers)
              linkedSocial.contains(p)
                  ? GroupedRow(
                      leading: SocialProviderIcon(provider: p),
                      title: p.label,
                      additionalInfo: Text(
                        '連携済み',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                      trailing: Icon(
                        CupertinoIcons.checkmark_alt,
                        size: 20,
                        color: context.colors.accent,
                      ),
                    )
                  : GroupedRow(
                      leading: SocialProviderIcon(provider: p),
                      title: '${p.label} と連携',
                      titleColor: context.colors.accent,
                      showChevron: false,
                      onTap: isBusy ? null : () => onLink(p),
                    ),
          ],
        ),
        const SizedBox(height: 12),
        InsetGroupedSection(
          hasLeading: false,
          children: [
            GroupedRow(
              title: 'ログアウト',
              titleColor: context.colors.accent,
              showChevron: false,
              onTap: isBusy ? null : () => _confirmSignOut(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InsetGroupedSection(
          hasLeading: false,
          footer: '記録・画像・お気に入りを含むすべてのデータが削除されます。',
          children: [
            GroupedRow(
              title: 'アカウントを完全に削除',
              titleColor: context.colors.destructive,
              showChevron: false,
              onTap: isBusy ? null : () => _confirmDelete(context),
            ),
          ],
        ),
      ],
    );
  }
}
