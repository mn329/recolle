import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';

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
              ? context.colors.textDisabled
              : color ?? context.colors.accent,
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
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontSize: 17,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
          color: onPressed == null
              ? context.colors.textDisabled
              : context.colors.accent,
        ),
      ),
    );
  }
}

/// タブのトップ画面用。スクロールで縮むラージタイトルと、引っ張って更新を備える。
///
/// [contentKey] が変わる（セグメントや絞り込みを切り替える）と、表示ごとに覚えた
/// スクロール位置へ戻す。初めて開く表示は、ナビバーの縮み具合を保ったまま先頭から見せる。
class LargeTitleScrollView extends StatefulWidget {
  const LargeTitleScrollView({
    super.key,
    required this.title,
    required this.slivers,
    this.enTitle,
    this.trailing,
    this.bottom,
    this.onRefresh,
    this.contentKey,
  });

  /// 画面の見出し。[enTitle] があれば、大見出しでは英字の横に小さく添える。
  final String title;

  /// 印字風の英字で大きく出す見出し（ホームの「RECOLLE」など）。縮んだときもこちらを出す。
  final String? enTitle;
  final Widget? trailing;

  /// タイトルの下に固定する部品（セグメントコントロールなど）。
  final PreferredSizeWidget? bottom;
  final Future<void> Function()? onRefresh;
  final List<Widget> slivers;

  /// 表示中の内容を表すキー。変わるとスクロール位置を表示ごとに切り替える。
  final Object? contentKey;

  @override
  State<LargeTitleScrollView> createState() => _LargeTitleScrollViewState();
}

class _LargeTitleScrollViewState extends State<LargeTitleScrollView> {
  /// ラージタイトルが縮みきるまでのスクロール量（CupertinoSliverNavigationBar の固定値）。
  static const double _largeTitleExtent = 52;

  final _savedOffsets = <Object?, double>{};

  /// CupertinoPageScaffold の内側の context。ステータスバーのタップで先頭へ戻る動きを
  /// 残すため、自前の controller ではなくそこで渡される PrimaryScrollController を使う。
  BuildContext? _scrollContext;

  ScrollController? get _controller {
    final scrollContext = _scrollContext;
    if (scrollContext == null || !scrollContext.mounted) return null;
    final controller = PrimaryScrollController.maybeOf(scrollContext);
    return controller != null && controller.hasClients ? controller : null;
  }

  @override
  void didUpdateWidget(LargeTitleScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (oldWidget.contentKey == widget.contentKey || controller == null) {
      return;
    }
    final current = controller.offset;
    _savedOffsets[oldWidget.contentKey] = current;
    final target =
        _savedOffsets[widget.contentKey] ??
        current.clamp(0, _largeTitleExtent).toDouble();
    // 新しい内容の長さが決まってから動かす（build 中に位置を変えると通知が走るため）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _controller;
      if (!mounted || controller == null) return;
      final position = controller.position;
      controller.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // CupertinoPageScaffold の下に置くと、スクロール前はナビバーの背景と区切り線が消える
    return CupertinoPageScaffold(
      backgroundColor: context.colors.background,
      child: Builder(
        builder: (scrollContext) {
          _scrollContext = scrollContext;
          return _buildScrollView(scrollContext);
        },
      ),
    );
  }

  Widget _largeTitle(BuildContext context) {
    final en = widget.enTitle;
    if (en == null) return Text(widget.title);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          en,
          style: AppFonts.displayStyle(
            fontSize: 38,
            color: context.colors.accent,
            letterSpacing: 3,
          ),
        ),
        // 英字と同じ名前（ホームの「RECOLLE」）なら添えない
        if (widget.title != en) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _middleTitle(BuildContext context) {
    final en = widget.enTitle;
    if (en == null) return Text(widget.title);
    return Text(
      en,
      style: AppFonts.displayStyle(
        fontSize: 22,
        color: context.colors.accent,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildScrollView(BuildContext context) {
    final refresh = widget.onRefresh;
    final bottom = widget.bottom;
    return CustomScrollView(
      primary: true,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverNavigationBar(
          largeTitle: _largeTitle(context),
          middle: _middleTitle(context),
          alwaysShowMiddle: false,
          trailing: widget.trailing,
          backgroundColor: context.colors.bar,
          border: Border(
            bottom: BorderSide(color: context.colors.separator, width: 0.33),
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
        ...widget.slivers,
        SliverLayoutBuilder(
          builder: (context, constraints) {
            // タブバーの裏に最後の要素が隠れないようにする
            var height = MediaQuery.paddingOf(context).bottom + 24;
            // 切り替える画面では、内容が短くてもラージタイトルを縮めた位置まで
            // スクロールできるようにする。足りないと切り替えのたびにタイトルが開き、内容が上下に跳ねる
            if (widget.contentKey != null) {
              final untilCollapsed =
                  constraints.viewportMainAxisExtent +
                  _largeTitleExtent -
                  constraints.precedingScrollExtent;
              if (untilCollapsed > height) height = untilCollapsed;
            }
            return SliverToBoxAdapter(child: SizedBox(height: height));
          },
        ),
      ],
    );
  }
}

/// 角丸のカードに行を並べる、iOS の設定アプリ風のグループ。
/// 画面内のセクション見出しの文字。本文より大きく明るくして、見出しだと分かるようにする。
TextStyle sectionHeaderTextStyle(BuildContext context) => TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w700,
  color: context.colors.textPrimary,
);

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
      backgroundColor: context.colors.background,
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      separatorColor: context.colors.separator,
      hasLeading: hasLeading,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      // 見出しと注記は、設定アプリと同じく行の文字の左端に揃える
      header: header == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(header!, style: sectionHeaderTextStyle(context)),
            ),
      footer: footer == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                footer!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: context.colors.textSecondary,
                ),
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
      backgroundColorActivated: context.colors.cardPressed,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 11, 14, 11),
      leading: leading,
      leadingSize: 30,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: titleColor ?? context.colors.textPrimary,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            ),
      additionalInfo: additionalInfo,
      trailing: chevron
          ? Icon(
              CupertinoIcons.chevron_forward,
              size: 17,
              color: context.colors.textDisabled,
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
        color: _pressed ? context.colors.cardPressed : const Color(0x00000000),
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
                    style: TextStyle(
                      fontSize: 16,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textSecondary,
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
  const RowIcon(this.icon, {super.key, this.color});

  final IconData icon;

  /// 省略時はアクセントカラー。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? context.colors.accent,
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
        backgroundColor: context.colors.fill,
        thumbColor: context.colors.segmentThumb,
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
                  color: context.colors.textPrimary,
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
          color: selected ? context.colors.accent : context.colors.fill,
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
                color: selected
                    ? context.colors.onAccent
                    : context.colors.textPrimary,
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
            Icon(icon, size: 56, color: context.colors.textDisabled),
            const SizedBox(height: 16),
            if (title != null) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.55,
                color: context.colors.textSecondary,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              CupertinoButton.tinted(
                color: context.colors.accent,
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: TextStyle(
                    color: context.colors.accent,
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
