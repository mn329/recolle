import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:recolle/components/scaffold_with_navbar.dart';
import 'package:recolle/core/theme/app_theme.dart';

/// 詳細画面を Navigator.push で積める、タブの最初の画面。
class _TabRoot extends StatelessWidget {
  const _TabRoot(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CupertinoButton(
        onPressed: () => Navigator.of(context).push(
          CupertinoPageRoute<void>(
            builder: (_) => Scaffold(body: Center(child: Text('$name の詳細'))),
          ),
        ),
        child: Text('$name を開く'),
      ),
    );
  }
}

Future<void> _pumpShell(WidgetTester tester) async {
  const paths = ['/', '/insights', '/favorites', '/account'];
  final router = GoRouter(
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            ScaffoldWithNavBar(navigationShell: shell),
        branches: [
          for (final path in paths)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: path,
                  builder: (context, state) => _TabRoot(path),
                ),
              ],
            ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('表示中のタブをもう一度押すと、そのタブの最初の画面へ戻る', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.text('/ を開く'));
    await tester.pumpAndSettle();
    expect(find.text('/ の詳細'), findsOneWidget);

    await tester.tap(find.text('ホーム'));
    await tester.pumpAndSettle();
    expect(find.text('/ の詳細'), findsNothing);
    expect(find.text('/ を開く'), findsOneWidget);
  });

  testWidgets('別のタブへ移っても、元のタブで開いていた画面は残す', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.text('/ を開く'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('お気に入り'));
    await tester.pumpAndSettle();
    expect(find.text('/favorites を開く'), findsOneWidget);

    await tester.tap(find.text('ホーム'));
    await tester.pumpAndSettle();
    expect(find.text('/ の詳細'), findsOneWidget);
  });
}
