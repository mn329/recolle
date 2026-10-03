import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:recolle/core/demo/demo_data.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/records/providers/records_provider.dart';

/// App Store 用のスクリーンショットを撮るためのデモモード。
///
/// `flutter run --dart-define=DEMO_MODE=true` のように指定したときだけ、サーバーの代わりに
/// [demoRecords] のデータを表示する。指定しなければ `false` の定数なので、
/// リリースビルドではこのファイルの処理は取り除かれる。
const bool kDemoMode = bool.fromEnvironment('DEMO_MODE');

/// デモモードで差し替える Provider。サーバーには何も書き込まない。
List<Override> demoOverrides() => [
  recordsProvider.overrideWith(
    (ref) => Stream.value(demoRecords(DateTime.now())),
  ),
  favoriteArtistsProvider.overrideWith(_DemoFavorites.new),
];

class _DemoFavorites extends FavoriteArtistsNotifier {
  @override
  Future<List<FavoriteArtist>> build() async => demoFavorites(DateTime.now());

  // 画像の置き換えなどでサーバーに問い合わせない。操作しても表示は変えない。
  @override
  Future<FavoriteArtist> add({required String name, int? itunesArtistId}) {
    throw UnsupportedError('デモモードでは追加できません');
  }

  @override
  Future<void> remove(String id) async {}
}
