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
class LiquidGlassTabBar extends StatelessWidget {
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

  final List<LiquidGlassTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
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
          shape: const LiquidRoundedSuperellipse(borderRadius: height / 2),
          child: GlassGlow(
            glowColor: const Color(0x33FFFFFF),
            child: SizedBox(
              height: height,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth =
                      (constraints.maxWidth - _indicatorInset * 2) /
                      items.length;
                  return Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOutBack,
                        left: _indicatorInset + itemWidth * currentIndex,
                        top: _indicatorInset,
                        bottom: _indicatorInset,
                        width: itemWidth,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0x24FFFFFF),
                            borderRadius: BorderRadius.all(
                              Radius.circular(height / 2 - _indicatorInset),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _indicatorInset,
                        ),
                        child: Row(
                          children: [
                            for (final (i, item) in items.indexed)
                              Expanded(
                                child: _TabButton(
                                  item: item,
                                  selected: i == currentIndex,
                                  onTap: () => onTap(i),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [Stack] の中で画面下に配置するためのラッパー。
  static Widget positioned(BuildContext context, {required Widget child}) {
    return Positioned(
      left: _horizontalMargin,
      right: _horizontalMargin,
      bottom: bottomOffset(context),
      child: child,
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
