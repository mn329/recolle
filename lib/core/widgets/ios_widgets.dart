import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:recolle/core/theme/app_colors.dart';

/// ナビゲーションバーに置くアイコンボタン。iOS と同じく押下中は淡くなる。
class NavBarIconButton extends StatelessWidget {
  const NavBarIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(40, 44),
        onPressed: onPressed,
        child: Icon(
          icon,
          size: 24,
          color: onPressed == null
              ? AppColors.textDisabled
              : color ?? AppColors.gold,
        ),
      ),
    );
  }
}

/// ナビゲーションバーの文字ボタン（「キャンセル」「保存」など）。
class NavBarTextButton extends StatelessWidget {
  const NavBarTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isBold = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      minimumSize: const Size(0, 44),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 17,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
          color: onPressed == null ? AppColors.textDisabled : AppColors.gold,
        ),
      ),
    );
  }
}

/// タブのトップ画面用。スクロールで縮むラージタイトルと、引っ張って更新を備える。
class LargeTitleScrollView extends StatelessWidget {
  const LargeTitleScrollView({
    super.key,
    required this.title,
    required this.slivers,
    this.largeTitle,
    this.middle,
    this.trailing,
    this.bottom,
    this.onRefresh,
  });

  /// 縮んだときに中央に出す見出し。[largeTitle] 省略時は大見出しにも使う。
  final String title;
  final Widget? largeTitle;

  /// 縮んだときの見出しを文字以外で出したいときに指定する。
  final Widget? middle;
  final Widget? trailing;

  /// タイトルの下に固定する部品（セグメントコントロールなど）。
  final PreferredSizeWidget? bottom;
  final Future<void> Function()? onRefresh;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final refresh = onRefresh;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverNavigationBar(
          largeTitle: largeTitle ?? Text(title),
          middle: middle ?? Text(title),
          alwaysShowMiddle: false,
          trailing: trailing,
          backgroundColor: AppColors.bar,
          border: const Border(
            bottom: BorderSide(color: AppColors.separator, width: 0.33),
          ),
          // 遷移先は Material の AppBar なので、ナビバー同士の Hero 遷移は使わない
          transitionBetweenRoutes: false,
          bottom: bottom,
          bottomMode: bottom == null ? null : NavigationBarBottomMode.always,
        ),
        if (refresh != null)
          CupertinoSliverRefreshControl(
            onRefresh: () async {
              HapticFeedback.mediumImpact();
              await refresh();
            },
          ),
        ...slivers,
        // タブバーの裏に最後の要素が隠れないようにする
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
        ),
      ],
    );
  }
}

/// 角丸のカードに行を並べる、iOS の設定アプリ風のグループ。
class InsetGroupedSection extends StatelessWidget {
  const InsetGroupedSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.hasLeading = true,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;

  /// 行の先頭にアイコンがあるとき true（区切り線をアイコンの右から引く）。
  final bool hasLeading;

  @override
  Widget build(BuildContext context) {
    return CupertinoListSection.insetGrouped(
      backgroundColor: AppColors.background,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      separatorColor: AppColors.separator,
      hasLeading: hasLeading,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      header: header == null
          ? null
          : Text(
              header!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
      footer: footer == null
          ? null
          : Text(
              footer!,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
      children: children,
    );
  }
}

/// [InsetGroupedSection] の行。押下中は背景が明るくなる。
class GroupedRow extends StatelessWidget {
  const GroupedRow({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.additionalInfo,
    this.trailing,
    this.onTap,
    this.showChevron,
    this.titleColor,
  });

  final String title;
  final Widget? leading;
  final String? subtitle;
  final Widget? additionalInfo;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 省略時は [onTap] があれば山括弧を出す。
  final bool? showChevron;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final chevron = showChevron ?? (onTap != null && trailing == null);
    return CupertinoListTile(
      backgroundColorActivated: AppColors.cardPressed,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 11, 14, 11),
      leading: leading,
      leadingSize: 30,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: titleColor ?? AppColors.textPrimary,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
      additionalInfo: additionalInfo,
      trailing: chevron
          ? const Icon(
              CupertinoIcons.chevron_forward,
              size: 17,
              color: Color(0x4DEBEBF5),
            )
          : trailing,
      onTap: onTap,
    );
  }
}

/// ミュージックアプリの曲リストのような、アートワーク付きの行。押下中は背景が明るくなる。
class MediaListTile extends StatefulWidget {
  const MediaListTile({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  State<MediaListTile> createState() => _MediaListTileState();
}

class _MediaListTileState extends State<MediaListTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap != null && _pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _pressed ? AppColors.cardPressed : const Color(0x00000000),
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
        child: Row(
          children: [
            if (widget.leading != null) ...[
              widget.leading!,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?widget.trailing,
          ],
        ),
      ),
    );
  }
}

/// 設定アプリ風の、色付き角丸四角に白抜きアイコン。
class RowIcon extends StatelessWidget {
  const RowIcon(this.icon, {super.key, this.color = AppColors.gold});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: SizedBox.square(
        dimension: 30,
        child: Icon(icon, size: 18, color: CupertinoColors.white),
      ),
    );
  }
}

/// iOS のセグメントコントロール。切り替え時に軽い触覚フィードバックを返す。
class IosSegmentedControl<T extends Object> extends StatelessWidget {
  const IosSegmentedControl({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        backgroundColor: const Color(0x3D767680),
        thumbColor: const Color(0xFF636366),
        padding: const EdgeInsets.all(2),
        onValueChanged: (next) {
          if (next == null || next == value) return;
          HapticFeedback.selectionClick();
          onChanged(next);
        },
        children: {
          for (final MapEntry(:key, value: label) in segments.entries)
            key: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: key == value ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
        },
      ),
    );
  }
}

/// 絞り込みや候補に使うカプセル型の選択チップ。
class CapsuleChip extends StatelessWidget {
  const CapsuleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.avatar,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.fromLTRB(avatar == null ? 14 : 4, 4, 14, 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold : const Color(0x3D767680),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (avatar != null) ...[avatar!, const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? CupertinoColors.black : AppColors.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一覧が空のときの、アイコン・説明・操作ボタンの縦並び。
class IosEmptyState extends StatelessWidget {
  const IosEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.title,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String? title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            if (title != null) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.55,
                color: AppColors.textSecondary,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              CupertinoButton.tinted(
                color: AppColors.gold,
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
