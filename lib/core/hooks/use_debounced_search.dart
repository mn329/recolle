import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// [query] の入力が [delay] 止まってから [search] を実行し、その結果を返す。
///
/// 古い検索結果が新しい入力の結果を上書きしないよう、最新の実行分だけを反映する。
/// [query] が [minLength] 未満のときは検索せず [AsyncSnapshot.nothing] を返す。
AsyncSnapshot<List<T>> useDebouncedSearch<T>(
  String query,
  Future<List<T>> Function(String query) search, {
  Duration delay = const Duration(milliseconds: 400),
  int minLength = 1,
}) {
  final snapshot = useState<AsyncSnapshot<List<T>>>(
    const AsyncSnapshot.nothing(),
  );
  final generation = useRef(0);
  final context = useContext();
  final trimmed = query.trim();

  useEffect(() {
    final current = ++generation.value;
    bool isLatest() => context.mounted && current == generation.value;

    if (trimmed.length < minLength) return null;
    final timer = Timer(delay, () async {
      if (!isLatest()) return;
      snapshot.value = const AsyncSnapshot.waiting();
      try {
        final results = await search(trimmed);
        if (isLatest()) {
          snapshot.value = AsyncSnapshot.withData(
            ConnectionState.done,
            results,
          );
        }
      } catch (e, st) {
        if (isLatest()) {
          snapshot.value = AsyncSnapshot.withError(ConnectionState.done, e, st);
        }
      }
    });
    return timer.cancel;
  }, [trimmed]);

  // デバウンス待ちの間は直前の結果を出し続け、候補がちらつかないようにする
  return trimmed.length < minLength
      ? const AsyncSnapshot.nothing()
      : snapshot.value;
}
