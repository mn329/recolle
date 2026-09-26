import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:recolle/core/theme/app_colors.dart';

/// ボトムナビゲーションバーを持つScaffold
/// 各画面の共通枠組みとして機能します
class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({required this.navigationShell, super.key});

  /// 画面遷移を管理するシェル
  /// 現在のインデックスやブランチの切り替え機能を提供します
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    // NavigationBarThemeのスタイルはmain.dart（AppTheme）で一括管理されているため
    // ここではNavigationBarThemeウィジェットでラップする必要はありません
    return Scaffold(
      backgroundColor: AppColors.background,
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_border_rounded),
            selectedIcon: Icon(Icons.star_rounded),
            label: 'お気に入り',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'アカウント',
          ),
        ],
      ),
    );
  }
}
