import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:recolle/components/liquid_glass_tab_bar.dart';
import 'package:recolle/core/theme/app_colors.dart';

/// 画面下に浮かぶリキッドグラスのタブバーを持つ共通の枠組み。
///
/// 中身はタブバーの裏まで描画される。タブバーに隠れる高さは
/// `MediaQuery.paddingOf(context).bottom` に足してあるので、各画面はその分の余白を末尾に空ける。
class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({required this.navigationShell, super.key});

  /// 画面遷移を管理するシェル
  /// 現在のインデックスやブランチの切り替え機能を提供します
  final StatefulNavigationShell navigationShell;

  static const _items = [
    LiquidGlassTabItem(
      icon: CupertinoIcons.tickets,
      activeIcon: CupertinoIcons.tickets_fill,
      label: 'ホーム',
    ),
    LiquidGlassTabItem(
      icon: CupertinoIcons.star,
      activeIcon: CupertinoIcons.star_fill,
      label: 'お気に入り',
    ),
    LiquidGlassTabItem(
      icon: CupertinoIcons.person_crop_circle,
      activeIcon: CupertinoIcons.person_crop_circle_fill,
      label: 'アカウント',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      // キーボードはタブバーの上に重なればよく、枠組みごと縮める必要はない
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery(
              data: mediaQuery.copyWith(
                padding: mediaQuery.padding.copyWith(
                  bottom: LiquidGlassTabBar.occupiedHeight(context),
                ),
              ),
              child: navigationShell,
            ),
          ),
          LiquidGlassTabBar.positioned(
            context,
            child: LiquidGlassTabBar(
              items: _items,
              currentIndex: navigationShell.currentIndex,
              onTap: (index) {
                // 表示中のタブをもう一度押したら、iOS と同じくそのタブの最初の画面へ戻る
                navigationShell.goBranch(
                  index,
                  initialLocation: index == navigationShell.currentIndex,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
