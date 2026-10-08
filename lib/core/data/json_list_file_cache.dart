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
    // 書き込み中にアプリが落ちてもキャッシュが壊れないよう、別ファイルに書いてから置き換える
    // 同時に保存しても同じ一時ファイルを取り合わないよう、呼び出しごとに名前を変える
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temp.writeAsString(jsonEncode(items), flush: true);
    await temp.rename(file.path);
  }

  /// [userId] のキャッシュを消す（ログアウト・アカウント削除のあと、端末に残さないため）。
  /// 保存の途中で残った一時ファイルも一緒に消す。
  Future<void> delete(String userId) async {
    final file = await _fileForUser(userId);
    if (await file.exists()) await file.delete();
    final tempPrefix = '${p.basename(file.path)}.';
    await for (final entity in file.parent.list()) {
      if (entity is File &&
          p.basename(entity.path).startsWith(tempPrefix) &&
          entity.path.endsWith('.tmp')) {
        await entity.delete();
      }
    }
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
