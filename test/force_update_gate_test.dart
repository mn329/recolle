import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/app_update/force_update_gate.dart';
import 'package:recolle/core/app_update/force_update_provider.dart';

class _FakeSource implements ForceUpdateSource {
  _FakeSource(this.current, this.minimum);

  String current;
  String? minimum;

  @override
  Future<String> currentVersion() async => current;

  @override
  Future<String?> minimumVersion() async => minimum;
}

Future<void> _pump(
  WidgetTester tester,
  _FakeSource source, {
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [forceUpdateSourceProvider.overrideWithValue(source)],
      child: MaterialApp(
        builder: (context, child) => ForceUpdateGate(child: child!),
        home: Scaffold(
          body: Center(
            child: TextButton(onPressed: onTap, child: const Text('本文のボタン')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('古いバージョンでは全画面で止め、App Store へのボタンを出す', (tester) async {
    await _pump(tester, _FakeSource('1.1.3', '1.1.4'));

    expect(find.text('アップデートが必要です'), findsOneWidget);
    expect(find.text('App Store を開く'), findsOneWidget);
  });

  testWidgets('止めているあいだは下の画面を操作できない', (tester) async {
    final semantics = tester.ensureSemantics();
    var tapped = false;
    await _pump(
      tester,
      _FakeSource('1.1.3', '1.1.4'),
      onTap: () => tapped = true,
    );

    await tester.tap(find.text('本文のボタン'), warnIfMissed: false);
    expect(tapped, isFalse);
    expect(find.semantics.byLabel('本文のボタン'), findsNothing);
    semantics.dispose();
  });

  testWidgets('読み上げでは見出しとボタンを別々に読む', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _FakeSource('1.1.3', '1.1.4'));

    expect(find.semantics.byLabel('アップデートが必要です'), findsOneWidget);
    expect(find.semantics.byLabel('App Store を開く'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('入力中に止めたら、キーボードを閉じて入力も受け付けない', (tester) async {
    final source = _FakeSource('1.1.3', null);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [forceUpdateSourceProvider.overrideWithValue(source)],
        child: MaterialApp(
          builder: (context, child) => ForceUpdateGate(child: child!),
          home: Scaffold(
            body: TextField(focusNode: focusNode, autofocus: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);

    // 入力中に最低バージョンが上がり、アプリに戻ってきた
    source.minimum = '1.1.4';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('アップデートが必要です'), findsOneWidget);
    expect(focusNode.hasFocus, isFalse);
  });

  testWidgets('新しいバージョンでは何も出さない', (tester) async {
    await _pump(tester, _FakeSource('1.1.4', '1.1.4'));

    expect(find.text('アップデートが必要です'), findsNothing);
    expect(find.text('本文のボタン'), findsOneWidget);
  });

  testWidgets('アプリに戻ってきたら確認し直す', (tester) async {
    final source = _FakeSource('1.1.3', '1.1.4');
    await _pump(tester, source);
    expect(find.text('アップデートが必要です'), findsOneWidget);

    // App Store でアップデートして戻ってきた
    source.current = '1.1.4';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('アップデートが必要です'), findsNothing);
  });
}
