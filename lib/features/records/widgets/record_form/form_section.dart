import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';

/// 作成フォームの 1 グループ。iOS の設定画面と同じく、小さな見出しの下に角丸カードで行を並べる。
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.children,
    this.header,
    this.trailing,
    this.footer,
    this.wrapInCard = true,
  });

  final String? header;

  /// 見出しの右端に添える情報（曲数など）。
  final Widget? trailing;
  final String? footer;
  final List<Widget> children;

  /// false なら子要素をそのまま並べる（自前でカードを描く部品向け）。
  final bool wrapInCard;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      header!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          if (wrapInCard) FormCard(children: children) else ...children,
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                footer!,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 行を細い区切り線でつないだ角丸カード。
class FormCard extends StatelessWidget {
  const FormCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: AppColors.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) const FormDivider(),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// iOS のリストと同じく、左端を少し空けた 0.33pt の区切り線。
class FormDivider extends StatelessWidget {
  const FormDivider({super.key, this.indent = 16});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: const SizedBox(
        height: 0.33,
        child: ColoredBox(color: AppColors.separator),
      ),
    );
  }
}
