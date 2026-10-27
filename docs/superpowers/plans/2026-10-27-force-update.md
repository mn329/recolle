# 強制アップデート Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Supabase に置いた最低バージョンより古い iOS アプリを、起動時・復帰時に全画面でブロックして App Store へ誘導する。

**Architecture:** `app_config` テーブル（1 行）に `min_ios_version` を置く。アプリは `ForceUpdateNotifier`（Riverpod）で自分のバージョンと比べ、`MaterialApp.builder` の一番外側の `ForceUpdateGate` が結果に応じて全画面を重ねる。読めなかったときは直前の結果を保つ（初回は通す）。

**Tech Stack:** Flutter 3.47.8 / hooks_riverpod 3 / flutter_hooks / supabase_flutter 2.18 / package_info_plus（新規）/ url_launcher

**Spec:** `docs/superpowers/specs/2026-10-27-force-update-design.md`

## Global Constraints

- App Store ID: `6762868760`。開く URL は `https://apps.apple.com/app/id6762868760`（`LaunchMode.externalApplication`）
- 比べるのは `version`（`1.1.4`）だけ。ビルド番号は使わない
- 取得のタイムアウトは 5 秒
- 確認できない（オフライン・エラー・タイムアウト・行なし・不正な値）ときはブロックしない
- iOS 以外・Web・デモモード（`kDemoMode`）では確認しない
- 最低バージョンの初期値は `1.0.0`
- 文言: 見出し「アップデートが必要です」/ 本文「このバージョンはご利用いただけなくなりました。App Store から最新版にアップデートしてください。」/ ボタン「App Store を開く」
- コメント・テスト名は既存コードに合わせて日本語

## Review Focus

1. 一度ブロックされたあと、復帰時の再確認がオフラインで失敗した → ブロックを解かない（機内モードで抜けられない）。Task 2 にテストあり
2. Supabase が応答しない → 5 秒で諦めて通常どおり使える（スプラッシュや画面が固まらない）。Task 2 にテストあり
3. 最低バージョンが `1.2` や `1.2.x`、空文字など想定外の形 → 足りない桁は 0 扱い、不正なら止めない。Task 1 にテストあり
4. ブロック中に下の画面をタップ・VoiceOver で操作 → 届かない。Task 3 にテストあり
5. App Store から戻ってきても古いまま → ブロックが出続け、更新済みなら復帰時に消える。Task 3 にテストあり

> 設計書との差分: ゲートは `buildAppRoot` の中ではなく、`main.dart` の `builder` で `buildAppRoot` の外側に置く。`buildAppRoot` の既存テストは ProviderScope なしで動いており、そこに Riverpod を持ち込まないため。

---

### Task 1: バージョンの比較

**Files:**
- Create: `lib/core/app_update/app_version.dart`
- Test: `test/app_version_test.dart`

**Interfaces:**
- Produces: `List<int>? parseAppVersion(String value)`、`bool isOlderThan(String current, String minimum)`

- [ ] **Step 1: 失敗するテストを書く**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/app_update/app_version.dart';

void main() {
  group('parseAppVersion', () {
    test('3 桁までの数字を読み、足りない桁は 0 にする', () {
      expect(parseAppVersion('1.2.3'), [1, 2, 3]);
      expect(parseAppVersion('1.2'), [1, 2, 0]);
      expect(parseAppVersion('2'), [2, 0, 0]);
      expect(parseAppVersion(' 1.10.0 '), [1, 10, 0]);
    });

    test('形式が不正なら null', () {
      expect(parseAppVersion(''), isNull);
      expect(parseAppVersion('1.2.x'), isNull);
      expect(parseAppVersion('1.2.3.4'), isNull);
      expect(parseAppVersion('1..2'), isNull);
      expect(parseAppVersion('1.1.4+29'), isNull);
    });
  });

  group('isOlderThan', () {
    test('最低バージョンより古いときだけ true', () {
      expect(isOlderThan('1.1.3', '1.1.4'), isTrue);
      expect(isOlderThan('1.9.9', '2.0.0'), isTrue);
      expect(isOlderThan('1.1.4', '1.1.4'), isFalse);
      expect(isOlderThan('1.1.5', '1.1.4'), isFalse);
      expect(isOlderThan('1.10.0', '1.9.0'), isFalse);
    });

    test('桁数が違っても比べられる', () {
      expect(isOlderThan('1.1', '1.1.0'), isFalse);
      expect(isOlderThan('1.1', '1.1.1'), isTrue);
    });

    test('どちらかが読めないときは止めない', () {
      expect(isOlderThan('1.0.0', 'abc'), isFalse);
      expect(isOlderThan('', '9.9.9'), isFalse);
    });
  });
}
```

- [ ] **Step 2: 失敗を確認**

Run: `flutter test test/app_version_test.dart`
Expected: FAIL（`app_version.dart` がない）

- [ ] **Step 3: 実装**

```dart
/// `1.2.3` のようなバージョンを 3 桁の数字にする。足りない桁は 0。形式が不正なら null。
List<int>? parseAppVersion(String value) {
  final parts = value.trim().split('.');
  if (parts.length > 3) return null;
  final numbers = <int>[];
  for (final part in parts) {
    if (!RegExp(r'^\d+$').hasMatch(part)) return null;
    numbers.add(int.parse(part));
  }
  while (numbers.length < 3) {
    numbers.add(0);
  }
  return numbers;
}

/// [current] が [minimum] より古いか。どちらかが読めないときは false（止めない側に倒す）。
bool isOlderThan(String current, String minimum) {
  final c = parseAppVersion(current);
  final m = parseAppVersion(minimum);
  if (c == null || m == null) return false;
  for (var i = 0; i < 3; i++) {
    if (c[i] != m[i]) return c[i] < m[i];
  }
  return false;
}
```

- [ ] **Step 4: 通ることを確認**

Run: `flutter test test/app_version_test.dart`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add lib/core/app_update/app_version.dart test/app_version_test.dart
git commit -m "feat: 強制アップデート用のバージョン比較を追加"
```

---

### Task 2: 最低バージョンの取得と判定（＋マイグレーション）

**Files:**
- Create: `supabase/migrations/20261027100000_app_config.sql`
- Create: `lib/core/app_update/force_update_provider.dart`
- Modify: `pubspec.yaml`（`package_info_plus` を追加）
- Test: `test/force_update_provider_test.dart`

**Interfaces:**
- Consumes: `isOlderThan(String current, String minimum)`（Task 1）
- Produces:
  - `abstract interface class ForceUpdateSource { Future<String> currentVersion(); Future<String?> minimumVersion(); }`
  - `final forceUpdateSourceProvider = Provider<ForceUpdateSource>(...)`
  - `final forceUpdateProvider = NotifierProvider<ForceUpdateNotifier, bool>(...)`（true = ブロック）
  - `ForceUpdateNotifier.check()`（`Future<void>`。復帰時に呼ぶ）

- [ ] **Step 1: 依存を追加**

Run: `flutter pub add package_info_plus`
Expected: `pubspec.yaml` の dependencies に `package_info_plus` が入る

- [ ] **Step 2: マイグレーションを書く**

```sql
-- 強制アップデートの最低バージョン。アプリは起動時と復帰時に読み、これより古ければ App Store へ誘導する。
-- 値はダッシュボード（service role）から変える。

create table public.app_config (
  id boolean primary key default true check (id),
  min_ios_version text not null check (min_ios_version ~ '^\d+(\.\d+){0,2}$')
);

comment on table public.app_config is 'アプリ全体の設定（1 行だけ）。min_ios_version より古い iOS アプリは使えなくする';

alter table public.app_config enable row level security;

-- 起動直後は匿名サインイン前のこともあるので anon にも読ませる。書き込みのポリシーは作らない
create policy "app_config は誰でも読める"
  on public.app_config for select
  to anon, authenticated
  using (true);

insert into public.app_config (min_ios_version) values ('1.0.0');
```

- [ ] **Step 3: 失敗するテストを書く**

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/app_update/force_update_provider.dart';

class _FakeSource implements ForceUpdateSource {
  _FakeSource({this.current = '1.1.4', this.minimum});

  String current;
  Future<String?> Function()? minimum;

  @override
  Future<String> currentVersion() async => current;

  @override
  Future<String?> minimumVersion() => minimum?.call() ?? Future.value(null);
}

ProviderContainer _container(_FakeSource source) {
  final container = ProviderContainer(
    overrides: [forceUpdateSourceProvider.overrideWithValue(source)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<bool> _check(ProviderContainer container) async {
  container.read(forceUpdateProvider);
  await container.read(forceUpdateProvider.notifier).check();
  return container.read(forceUpdateProvider);
}

void main() {
  test('最低バージョンより古ければブロックする', () async {
    final source = _FakeSource(current: '1.1.3', minimum: () async => '1.1.4');
    expect(await _check(_container(source)), isTrue);
  });

  test('同じか新しければブロックしない', () async {
    final source = _FakeSource(current: '1.1.4', minimum: () async => '1.1.4');
    expect(await _check(_container(source)), isFalse);
  });

  test('最低バージョンがない（確認しない環境・行なし）ときはブロックしない', () async {
    final source = _FakeSource(current: '1.1.3', minimum: () async => null);
    expect(await _check(_container(source)), isFalse);
  });

  test('取得に失敗したらブロックしない', () async {
    final source = _FakeSource(
      current: '1.1.3',
      minimum: () async => throw Exception('offline'),
    );
    expect(await _check(_container(source)), isFalse);
  });

  test('一度ブロックしたら、再確認に失敗してもブロックしたまま', () async {
    final source = _FakeSource(current: '1.1.3', minimum: () async => '1.1.4');
    final container = _container(source);
    expect(await _check(container), isTrue);

    source.minimum = () async => throw Exception('offline');
    expect(await _check(container), isTrue);
  });

  test('アップデート後の再確認でブロックを解く', () async {
    final source = _FakeSource(current: '1.1.3', minimum: () async => '1.1.4');
    final container = _container(source);
    expect(await _check(container), isTrue);

    source.current = '1.1.4';
    expect(await _check(container), isFalse);
  });

  testWidgets('応答がなければ 5 秒で諦めてブロックしない', (tester) async {
    final never = Completer<String?>();
    final source = _FakeSource(current: '1.1.3', minimum: () => never.future);
    final container = _container(source);
    container.read(forceUpdateProvider);
    final done = container.read(forceUpdateProvider.notifier).check();

    await tester.pump(const Duration(seconds: 6));
    await done;
    expect(container.read(forceUpdateProvider), isFalse);
  });
}
```

- [ ] **Step 4: 失敗を確認**

Run: `flutter test test/force_update_provider_test.dart`
Expected: FAIL（`force_update_provider.dart` がない）

- [ ] **Step 5: 実装**

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:recolle/core/app_update/app_version.dart';
import 'package:recolle/core/demo/demo_mode.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 強制アップデートの判定に使う値の取り出し口。テストでは差し替える。
abstract interface class ForceUpdateSource {
  /// 動いているアプリのバージョン（`1.1.4` など。ビルド番号は含まない）
  Future<String> currentVersion();

  /// 最低バージョン。確認しない環境や、サーバーに値がないときは null
  Future<String?> minimumVersion();
}

class SupabaseForceUpdateSource implements ForceUpdateSource {
  const SupabaseForceUpdateSource();

  @override
  Future<String> currentVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  @override
  Future<String?> minimumVersion() async {
    // 配信しているのは App Store だけ。スクリーンショット撮影中も止めない
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS || kDemoMode) {
      return null;
    }
    final row = await Supabase.instance.client
        .from('app_config')
        .select('min_ios_version')
        .maybeSingle();
    return row?['min_ios_version'] as String?;
  }
}

final forceUpdateSourceProvider = Provider<ForceUpdateSource>(
  (ref) => const SupabaseForceUpdateSource(),
);

/// アップデートが必要（true）か。起動時に確認し、[ForceUpdateNotifier.check] で確認し直す。
final forceUpdateProvider = NotifierProvider<ForceUpdateNotifier, bool>(
  ForceUpdateNotifier.new,
);

class ForceUpdateNotifier extends Notifier<bool> {
  static const _timeout = Duration(seconds: 5);

  @override
  bool build() {
    unawaited(check());
    return false;
  }

  /// 確認できなかったときは直前の結果のまま（初回は使える側）。
  /// 一度ブロックしたあとに圏外にしても抜けられないようにするため。
  Future<void> check() async {
    final source = ref.read(forceUpdateSourceProvider);
    try {
      final minimum = await source.minimumVersion().timeout(_timeout);
      if (minimum == null) return;
      final current = await source.currentVersion();
      if (!ref.mounted) return;
      state = isOlderThan(current, minimum);
    } catch (e) {
      debugPrint('Force update check failed: $e');
    }
  }
}
```

- [ ] **Step 6: 通ることを確認**

Run: `flutter test test/force_update_provider_test.dart`
Expected: PASS（7 件）

- [ ] **Step 7: コミット**

```bash
git add pubspec.yaml pubspec.lock supabase/migrations/20261027100000_app_config.sql lib/core/app_update/force_update_provider.dart test/force_update_provider_test.dart
git commit -m "feat: Supabase の最低バージョンと比べて強制アップデートを判定する"
```

---

### Task 3: ブロック画面とアプリへの組み込み

**Files:**
- Create: `lib/core/app_update/force_update_gate.dart`
- Modify: `lib/main.dart`（`MaterialApp.router` の `builder`）
- Test: `test/force_update_gate_test.dart`

**Interfaces:**
- Consumes: `forceUpdateProvider`、`forceUpdateSourceProvider`、`ForceUpdateSource`、`ForceUpdateNotifier.check()`（Task 2）
- Produces: `class ForceUpdateGate extends HookConsumerWidget { const ForceUpdateGate({required Widget child}); static final Uri appStoreUrl; }`

- [ ] **Step 1: 失敗するテストを書く**

```dart
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

Future<void> _pump(WidgetTester tester, _FakeSource source, {VoidCallback? onTap}) async {
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
    await _pump(tester, _FakeSource('1.1.3', '1.1.4'), onTap: () => tapped = true);

    await tester.tap(find.text('本文のボタン'), warnIfMissed: false);
    expect(tapped, isFalse);
    expect(find.bySemanticsLabel('本文のボタン'), findsNothing);
    semantics.dispose();
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
```

- [ ] **Step 2: 失敗を確認**

Run: `flutter test test/force_update_gate_test.dart`
Expected: FAIL（`force_update_gate.dart` がない）

- [ ] **Step 3: 実装**

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/app_update/force_update_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// 最低バージョンより古いアプリを、全画面で止めて App Store へ誘導する。
///
/// [MaterialApp.builder] で全画面の一番外側に置く。止めているあいだは下の画面に操作も読み上げも届かない。
class ForceUpdateGate extends HookConsumerWidget {
  const ForceUpdateGate({super.key, required this.child});

  final Widget child;

  static final Uri appStoreUrl = Uri.parse(
    'https://apps.apple.com/app/id6762868760',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateRequired = ref.watch(forceUpdateProvider);

    // App Store から戻ってきたときなどに確認し直す
    useOnAppLifecycleStateChange((_, state) {
      if (state == AppLifecycleState.resumed) {
        ref.read(forceUpdateProvider.notifier).check();
      }
    });

    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(excluding: updateRequired, child: child),
        if (updateRequired) const _ForceUpdateScreen(),
      ],
    );
  }
}

class _ForceUpdateScreen extends StatelessWidget {
  const _ForceUpdateScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'アップデートが必要です',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'このバージョンはご利用いただけなくなりました。App Store から最新版にアップデートしてください。',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              CupertinoButton.filled(
                onPressed: _openAppStore,
                child: const Text('App Store を開く'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openAppStore() async {
  try {
    await launchUrl(
      ForceUpdateGate.appStoreUrl,
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    debugPrint('launchUrl failed for ${ForceUpdateGate.appStoreUrl}: $e');
  }
}
```

- [ ] **Step 4: 通ることを確認**

Run: `flutter test test/force_update_gate_test.dart`
Expected: PASS（4 件）

- [ ] **Step 5: `main.dart` に組み込む**

`lib/main.dart` の import に追加:

```dart
import 'package:recolle/core/app_update/force_update_gate.dart';
```

`MaterialApp.router` の `builder: buildAppRoot,` を次に置き換える:

```dart
      // 古いバージョンは全画面で止めて App Store へ誘導する（最低バージョンは Supabase の app_config）
      builder: (context, child) =>
          ForceUpdateGate(child: buildAppRoot(context, child)),
```

- [ ] **Step 6: 全体を確認**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`、すべて PASS

- [ ] **Step 7: コミット**

```bash
git add lib/core/app_update/force_update_gate.dart lib/main.dart test/force_update_gate_test.dart
git commit -m "feat: 古いバージョンを全画面で止めて App Store へ誘導する"
```

---

### Task 4: 実機相当での確認と PR

- [ ] **Step 1: シミュレーターで起動を確かめる**

`flutter build ios --simulator --debug` → シミュレーターにインストールして起動し、ブロックが出ずに通常の画面が出ることを確認する（本番にはまだ `app_config` がないので「読めない → 通す」の経路になる）。

- [ ] **Step 2: PR を作る**

base は `mn329/chore-upgrade-flutter-sdk`（#16）。本文に、マイグレーションを本番に適用する手順とリリース手順（設計書の「リリース」）を書く。

---

### Task 5: リリース（PR のマージ後）

- [ ] `supabase db push` などで本番（`kpcpymierumkzgevfoua`）に `20261027100000_app_config.sql` を適用し、`select * from app_config` が `1.0.0` を返すことを確認
- [ ] `pubspec.yaml` を `1.1.4+29` にしてコミット
- [ ] 本番の `.env` があることを確認してから `flutter build ipa --release`
- [ ] `asc builds upload --app 6762868760 --ipa build/ios/ipa/Recolle.ipa --wait`
- [ ] `asc builds add-groups --build-id $B --group d7ebf8f8-ddff-4bdc-a2be-57f283db578b --submit --confirm`
- [ ] ブロック画面の見た目を TestFlight 版で確認する: 本番の `min_ios_version` を一時的に `9.9.9` にして表示とボタンを確かめ、すぐ `1.0.0` に戻す（ゲート入りの版はまだストアに出ていないので、影響は TestFlight の確認者だけ）
- [ ] ユーザーが TestFlight で確認 → OK をもらう
- [ ] `asc release stage --app 6762868760 --version 1.1.4 --build-id $B --copy-metadata-from 1.1.3 --confirm` → 新機能の文言を `asc localizations update` → `asc review doctor` / `asc validate` → `asc review submit --app 6762868760 --version-id $V --build-id $B --confirm`
