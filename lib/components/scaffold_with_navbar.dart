import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:recolle/core/theme/app_colors.dart';

/// すりガラスの iOS タブバーを持つ共通の枠組み。
///
/// 中身はタブバーの裏まで描画される（[Scaffold.extendBody]）。各画面のスクロールは
/// `MediaQuery.paddingOf(context).bottom` 分の余白を末尾に足して、最後の要素が隠れないようにする。
class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({required this.navigationShell, super.key});

  /// 画面遷移を管理するシェル
  /// 現在のインデックスやブランチの切り替え機能を提供します
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: CupertinoTabBar(
        currentIndex: navigationShell.currentIndex,
        backgroundColor: AppColors.bar,
        activeColor: AppColors.gold,
        inactiveColor: const Color(0xFF8E8E93),
        iconSize: 26,
        height: 54,
        border: const Border(
          top: BorderSide(color: AppColors.separator, width: 0.33),
        ),
        onTap: (index) {
          if (index != navigationShell.currentIndex) {
            HapticFeedback.selectionClick();
          }
          // 表示中のタブをもう一度押したら、iOS と同じくそのタブの最初の画面へ戻る
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.tickets),
            activeIcon: Icon(CupertinoIcons.tickets_fill),
            label: 'ホーム',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.star),
            activeIcon: Icon(CupertinoIcons.star_fill),
            label: 'お気に入り',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_crop_circle),
            activeIcon: Icon(CupertinoIcons.person_crop_circle_fill),
            label: 'アカウント',
          ),
        ],
      ),
    );
  }
}
