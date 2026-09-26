import 'dart:io';

import 'package:recolle/features/records/models/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecordsRepository {
  RecordsRepository(this._client);

  final SupabaseClient _client;

  Future<Record> insertRecord(Map<String, dynamic> row) async {
    final inserted = await _client
        .from('records')
        .insert(row)
        .select()
        .single();
    final map = Map<String, dynamic>.from(inserted as Map);
    return Record.fromJson(map);
  }

  Future<void> deleteRecord(String id) async {
    await _client.from('records').delete().eq('id', id);
  }

  Future<Record> updateRecord(String id, Map<String, dynamic> row) async {
    final updated = await _client
        .from('records')
        .update(row)
        .eq('id', id)
        .select()
        .single();
    final map = Map<String, dynamic>.from(updated as Map);
    return Record.fromJson(map);
  }

  /// アップロード後の公開 URL を返す。
  Future<String> uploadTicketImage({
    required String userId,
    required File file,
  }) async {
    final baseName =
        '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final storagePath = '$userId/$baseName';
    await _client.storage.from('ticket-images').upload(storagePath, file);
    return _client.storage.from('ticket-images').getPublicUrl(storagePath);
  }
}
