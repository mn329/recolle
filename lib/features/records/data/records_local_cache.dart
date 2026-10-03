import 'package:recolle/core/data/json_list_file_cache.dart';
import 'package:recolle/features/records/models/record.dart';

/// オンライン同期時に保存し、オフライン閲覧用に読み出すローカルキャッシュ。
class RecordsLocalCache {
  static const _cache = JsonListFileCache('records_cache');

  /// このユーザーの記録のキャッシュを消す。
  static Future<void> clear(String userId) => _cache.delete(userId);

  Future<void> save(String userId, List<Record> records) {
    return _cache.save(userId, [
      for (final r in records) <String, dynamic>{...r.toJson(), 'id': r.id},
    ]);
  }

  /// 保存した記録を手元のキャッシュにも反映する（再読み込みの先頭で古い内容が出るのを防ぐ）。
  Future<void> upsert(String userId, Record record) async {
    final records = await load(userId);
    await save(userId, [record, ...records.where((r) => r.id != record.id)]);
  }

  /// 削除した記録を手元のキャッシュからも外す（再読み込みで一瞬戻って見えるのを防ぐ）。
  Future<void> remove(String userId, String recordId) async {
    final records = await load(userId);
    await save(userId, [
      for (final r in records)
        if (r.id != recordId) r,
    ]);
  }

  Future<List<Record>> load(String userId) async {
    final rows = await _cache.load(userId);
    return [for (final row in rows) Record.fromJson(row)];
  }
}
