import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// ユーザーごとに JSON 配列をファイル保存する、オフライン閲覧用のキャッシュ。
class JsonListFileCache {
  const JsonListFileCache(this.fileNamePrefix);

  final String fileNamePrefix;

  Future<File> _fileForUser(String userId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, '${fileNamePrefix}_$userId.json'));
  }

  Future<void> save(String userId, List<Map<String, dynamic>> items) async {
    final file = await _fileForUser(userId);
    await file.writeAsString(jsonEncode(items));
  }

  /// 読めない・壊れている場合は空として扱う（キャッシュは再同期で復元できるため）。
  Future<List<Map<String, dynamic>>> load(String userId) async {
    try {
      final file = await _fileForUser(userId);
      if (!await file.exists()) return const [];
      final text = await file.readAsString();
      if (text.isEmpty) return const [];
      final decoded = jsonDecode(text) as List<dynamic>;
      return [for (final e in decoded) Map<String, dynamic>.from(e as Map)];
    } catch (e) {
      debugPrint('JsonListFileCache($fileNamePrefix) load failed: $e');
      return const [];
    }
  }
}
