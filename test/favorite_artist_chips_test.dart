import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/widgets/favorite_artist_chips.dart';

class _Bar extends StatelessWidget implements PreferredSizeWidget {
  const _Bar(this.child);

  final Widget child;

  @override
  Size get preferredSize => const Size.fromHeight(FavoriteArtistChips.height);

  @override
  Widget build(BuildContext context) => child;
}

class _Screen extends HookWidget {
  const _Screen(this.favorites);

  final List<FavoriteArtist> favorites;

  @override
  Widget build(BuildContext context) {
    final selected = useState<String?>(null);
    return Scaffold(
      body: LargeTitleScrollView(
        title: 'テスト',
        contentKey: ('artist', selected.value),
        bottom: _Bar(
          FavoriteArtistChips(
            favorites: favorites,
            selectedName: selected.value,
            onSelected: (name) => selected.value = name,
          ),
        ),
        slivers: [
          SliverList.list(
            children: [
              for (var i = 0; i < (selected.value == null ? 40 : 1); i++)
                SizedBox(height: 100, child: Text('${selected.value}-$i')),
            ],
          ),
        ],
      ),
    );
  }
}

void main() {
  final favorites = [
    for (var i = 0; i < 12; i++)
      FavoriteArtist(id: '$i', name: 'Artist$i', createdAt: DateTime(2026)),
  ];

  ScrollPosition chipPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(FavoriteArtistChips),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  testWidgets('チップを切り替えても、チップ列の横位置もタイトルの縮み具合も変わらない', (tester) async {
    // 横向きではラージタイトルが出ないので、iPhone の縦向きで確かめる
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: _Screen(favorites)),
    );
    await tester.pumpAndSettle();

    // 内容を下にスクロールしてナビバーを縮めた状態から選ぶ
    await tester.drag(find.text('null-3'), const Offset(0, -600));
    await tester.pumpAndSettle();

    chipPosition(tester).jumpTo(600);
    await tester.pumpAndSettle();
    final chip = find.widgetWithText(CapsuleChip, 'Artist6');
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    final before = chipPosition(tester).pixels;

    final chipsBottom = tester
        .getBottomLeft(find.byType(FavoriteArtistChips))
        .dy;
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(chipPosition(tester).pixels, before);
    // 記録が 1 件でもラージタイトルが開き直さず、内容がチップ列のすぐ下から始まる
    expect(tester.getTopLeft(find.text('Artist6-0')).dy, chipsBottom);

    await tester.tap(find.widgetWithText(CapsuleChip, 'Artist6'));
    await tester.pumpAndSettle();
    expect(chipPosition(tester).pixels, before);
  });
}
