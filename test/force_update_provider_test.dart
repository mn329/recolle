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
