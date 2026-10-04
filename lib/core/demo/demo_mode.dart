import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:recolle/core/demo/demo_data.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/records/data/records_repository.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';

/// App Store 用のスクリーンショットを撮るためのデモモード。
///
/// `flutter run --dart-define=DEMO_MODE=true` のように指定したときだけ、サーバーの代わりに
/// [demoRecords] のデータを表示し、記録の作成・編集・削除もメモリ上だけで行う（サーバーには何も書き込まない）。
/// 指定しなければ `false` の定数なので、リリースビルドではこのファイルの処理は取り除かれる。
const bool kDemoMode = bool.fromEnvironment('DEMO_MODE');

/// デモモードで差し替える Provider。サーバーには何も書き込まない。
List<Override> demoOverrides() => [
  recordsProvider.overrideWith((ref) async* {
    yield ref.watch(_demoRecordsStoreProvider);
  }),
  recordsRepositoryProvider.overrideWith(
    (ref) =>
        _DemoRecordsRepository(ref.read(_demoRecordsStoreProvider.notifier)),
  ),
  favoriteArtistsProvider.overrideWith(_DemoFavorites.new),
];

class _DemoRecordsStore extends Notifier<List<Record>> {
  @override
  List<Record> build() => demoRecords(DateTime.now());

  void upsert(Record record) =>
      state = [record, ...state.where((r) => r.id != record.id)];

  void remove(String id) => state = [...state.where((r) => r.id != id)];
}

final _demoRecordsStoreProvider =
    NotifierProvider<_DemoRecordsStore, List<Record>>(_DemoRecordsStore.new);

/// サーバーの代わりに、メモリ上の一覧へ書き込む記録の保存先。画像はアップロードしない。
class _DemoRecordsRepository implements RecordsRepository {
  _DemoRecordsRepository(this._store);

  final _DemoRecordsStore _store;

  @override
  Future<Record> insertRecord(Map<String, dynamic> row) async {
    final record = Record.fromJson(Map<String, dynamic>.from(row));
    _store.upsert(record);
    return record;
  }

  @override
  Future<Record> updateRecord(String id, Map<String, dynamic> row) async {
    final record = Record.fromJson({...row, 'id': id});
    _store.upsert(record);
    return record;
  }

  @override
  Future<void> deleteRecord(String id) async => _store.remove(id);

  @override
  Future<String> uploadTicketImage({
    required String userId,
    required File file,
  }) async => '';

  @override
  Future<void> deleteTicketImages(List<String> urls) async {}
}

class _DemoFavorites extends FavoriteArtistsNotifier {
  @override
  Future<List<FavoriteArtist>> build() async => demoFavorites(DateTime.now());

  // 画像の置き換えなどでサーバーに問い合わせず、メモリ上だけで追加・削除する
  @override
  Future<FavoriteArtist> add({
    required String name,
    int? itunesArtistId,
  }) async {
    final added = FavoriteArtist(
      id: 'demo-fav-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      createdAt: DateTime.now(),
    );
    state = AsyncData([...?state.asData?.value, added]);
    return added;
  }

  @override
  Future<void> remove(String id) async {
    state = AsyncData([
      for (final f in state.asData?.value ?? const <FavoriteArtist>[])
        if (f.id != id) f,
    ]);
  }
}
