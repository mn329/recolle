import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:recolle/core/theme/app_colors.dart';

class LiquidGlassTabItem {
  const LiquidGlassTabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// iOS 26 風の、画面下に浮かぶリキッドグラスのタブバー。
///
/// タップのほか、長押しや横スワイプで選択中のピルを指で動かし、離した位置のタブへ切り替えられる。
class LiquidGlassTabBar extends StatefulWidget {
  const LiquidGlassTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  static const double height = 64;
  static const double _horizontalMargin = 24;
  static const double _indicatorInset = 5;

  /// 画面下端からタブバー下端までの距離。
  static double bottomOffset(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return safeBottom > 0 ? safeBottom - 10 : 12;
  }

  /// タブバーに隠れないよう、中身の末尾に空けるべき高さ。
  static double occupiedHeight(BuildContext context) =>
      bottomOffset(context) + height + 8;

  /// [Stack] の中で画面下に配置するためのラッパー。
  static Widget positioned(BuildContext context, {required Widget child}) {
    return Positioned(
      left: _horizontalMargin,
      right: _horizontalMargin,
      bottom: bottomOffset(context),
      child: child,
    );
  }

  final List<LiquidGlassTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  State<LiquidGlassTabBar> createState() => _LiquidGlassTabBarState();
}

class _LiquidGlassTabBarState extends State<LiquidGlassTabBar> {
  static const _inset = LiquidGlassTabBar._indicatorInset;

  /// ドラッグ中の指の x 座標（タブバー左端基準）。ドラッグしていなければ null。
  double? _dragX;
  double _itemWidth = 0;

  int _indexAt(double x) =>
      ((x - _inset) / _itemWidth).floor().clamp(0, widget.items.length - 1);

  int? get _hoveredIndex => _dragX == null ? null : _indexAt(_dragX!);

  void _startDrag(double x) {
    HapticFeedback.lightImpact();
    setState(() => _dragX = x);
  }

  void _updateDrag(double x) {
    final before = _hoveredIndex;
    setState(() => _dragX = x);
    if (_hoveredIndex != before) HapticFeedback.selectionClick();
  }

  void _endDrag() {
    final target = _hoveredIndex;
    setState(() => _dragX = null);
    if (target != null && target != widget.currentIndex) widget.onTap(target);
  }

  void _cancelDrag() => setState(() => _dragX = null);

  @override
  Widget build(BuildContext context) {
    final dragging = _dragX != null;
    final highlightedIndex = _hoveredIndex ?? widget.currentIndex;

    return LiquidGlassLayer(
      // リキッドグラスのシェーダーは Impeller 専用。それ以外は軽量なすりガラスで代用する
      fake: !ImageFilter.isShaderFilterSupported,
      settings: const LiquidGlassSettings(
        thickness: 18,
        blur: 12,
        glassColor: Color(0x33303036),
        lightIntensity: 0.9,
        ambientStrength: 0.4,
        refractiveIndex: 1.25,
        saturation: 1.6,
      ),
      child: LiquidStretch(
        stretch: 0.3,
        interactionScale: 1.03,
        child: LiquidGlass(
          shape: const LiquidRoundedSuperellipse(
            borderRadius: LiquidGlassTabBar.height / 2,
          ),
          child: GlassGlow(
            glowColor: const Color(0x33FFFFFF),
            child: SizedBox(
              height: LiquidGlassTabBar.height,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _itemWidth =
                      (constraints.maxWidth - _inset * 2) / widget.items.length;
                  final restingLeft = _inset + _itemWidth * widget.currentIndex;
                  final indicatorLeft = dragging
                      ? (_dragX! - _itemWidth / 2).clamp(
                          _inset,
                          constraints.maxWidth - _inset - _itemWidth,
                        )
                      : restingLeft;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: (d) => _startDrag(d.localPosition.dx),
                    onLongPressMoveUpdate: (d) =>
                        _updateDrag(d.localPosition.dx),
                    onLongPressEnd: (_) => _endDrag(),
                    onLongPressCancel: _cancelDrag,
                    onHorizontalDragStart: (d) =>
                        _startDrag(d.localPosition.dx),
                    onHorizontalDragUpdate: (d) =>
                        _updateDrag(d.localPosition.dx),
                    onHorizontalDragEnd: (_) => _endDrag(),
                    onHorizontalDragCancel: _cancelDrag,
                    child: Stack(
                      children: [
                        AnimatedPositioned(
                          // 指に追従している間は遅延なく動かし、離したらタブの位置へ弾むように戻す
                          duration: dragging
                              ? Duration.zero
                              : const Duration(milliseconds: 380),
                          curve: Curves.easeOutBack,
                          left: indicatorLeft,
                          top: _inset,
                          bottom: _inset,
                          width: _itemWidth,
                          child: AnimatedScale(
                            scale: dragging ? 1.12 : 1,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutBack,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              decoration: BoxDecoration(
                                color: dragging
                                    ? const Color(0x3DFFFFFF)
                                    : const Color(0x24FFFFFF),
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(
                                    LiquidGlassTabBar.height / 2 - _inset,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: _inset,
                          ),
                          child: Row(
                            children: [
                              for (final (i, item) in widget.items.indexed)
                                Expanded(
                                  child: _TabButton(
                                    item: item,
                                    selected: i == highlightedIndex,
                                    onTap: () => widget.onTap(i),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final LiquidGlassTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.gold : const Color(0xFFD1D1D6);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!selected) HapticFeedback.selectionClick();
          onTap();
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                selected ? item.activeIcon : item.icon,
                key: ValueKey(selected),
                size: 25,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
