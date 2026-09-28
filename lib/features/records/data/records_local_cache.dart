import 'package:recolle/core/data/json_list_file_cache.dart';
import 'package:recolle/features/records/models/record.dart';

/// オンライン同期時に保存し、オフライン閲覧用に読み出すローカルキャッシュ。
class RecordsLocalCache {
  static const _cache = JsonListFileCache('records_cache');

  Future<void> save(String userId, List<Record> records) {
    return _cache.save(userId, [
      for (final r in records) <String, dynamic>{...r.toJson(), 'id': r.id},
    ]);
  }

  Future<List<Record>> load(String userId) async {
    final rows = await _cache.load(userId);
    return [for (final row in rows) Record.fromJson(row)];
  }
}
