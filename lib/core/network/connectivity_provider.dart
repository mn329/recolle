import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `connectivity_plus` の結果から「オンラインとみなす」かどうか。
///
/// 空リストは環境によって「不明」のためオンライン扱いにし、実通信失敗は各操作のエラーに任せる。
bool isConnectivityOnline(List<ConnectivityResult> results) {
  if (results.isEmpty) {
    return true;
  }
  return !results.contains(ConnectivityResult.none);
}

final connectivityProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) async* {
  yield await Connectivity().checkConnectivity();
  yield* Connectivity().onConnectivityChanged;
});

/// オフライン時は閲覧のみとし、作成・編集・削除を抑止する。
final isOfflineReadOnlyProvider = Provider<bool>((ref) {
  final c = ref.watch(connectivityProvider);
  return c.maybeWhen(
    data: (r) => !isConnectivityOnline(r),
    orElse: () => false,
  );
});
