import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:recolle/core/utils/ticket_image_compress.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:recolle/core/widgets/decoded_network_image.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 記録の書き込みに応答がなかった。サーバー側では反映されている可能性がある。
///
/// 新しい記録は ID をアプリで決めて upsert するので、同じ内容で保存し直しても二重にはならない。
class RecordWriteUncertain extends UserFacingException {
  const RecordWriteUncertain()
    : super('保存できたか確認できませんでした。電波の良い場所でもう一度保存してください（同じ記録が二重になることはありません）。');
}

class RecordsRepository {
  RecordsRepository(this._client);

  final SupabaseClient _client;

  /// supabase_flutter の通信は既定でタイムアウトしないため、電波の弱い会場で保存が終わらなくならないよう区切る。
  static const _writeTimeout = Duration(seconds: 20);
  static const _uploadTimeout = Duration(seconds: 60);

  /// 新しい記録を保存する。[row] には アプリで決めた `id` を入れる（保存し直しても 1 件のままにするため）。
  Future<Record> insertRecord(Map<String, dynamic> row) async {
    final inserted = await _write(
      _client.from('records').upsert(row).select().single(),
    );
    return Record.fromJson(Map<String, dynamic>.from(inserted as Map));
  }

  Future<void> deleteRecord(String id) async {
    await _client.from('records').delete().eq('id', id);
  }

  Future<Record> updateRecord(String id, Map<String, dynamic> row) async {
    final updated = await _write(
      _client.from('records').update(row).eq('id', id).select().single(),
    );
    return Record.fromJson(Map<String, dynamic>.from(updated as Map));
  }

  static Future<T> _write<T>(Future<T> request) => request.timeout(
    _writeTimeout,
    onTimeout: () => throw const RecordWriteUncertain(),
  );

  static const bucket = 'ticket-images';

  /// アップロードした画像の URL を返す。
  ///
  /// バケットは非公開で、この URL はバケット内の場所を表す識別子として保存する。
  /// 表示は [ticketImageStoragePath] で場所を取り出し、ログイン中のユーザーの権限で取得する。
  Future<String> uploadTicketImage({
    required String userId,
    required File file,
  }) async {
    final baseName =
        '${DateTime.now().microsecondsSinceEpoch}_${file.path.split('/').last}';
    final storagePath = '$userId/$baseName';
    await _client.storage
        .from(bucket)
        .upload(storagePath, file)
        .timeout(
          _uploadTimeout,
          onTimeout: () => throw const UserFacingException(
            '画像のアップロードがタイムアウトしました。電波の良い場所でもう一度お試しください。',
          ),
        );
    // 一覧に出す小さな画像も一緒に上げる。失敗しても、大きな画像だけで表示できる
    unawaited(_uploadThumbnail(storagePath, file));
    return _client.storage.from(bucket).getPublicUrl(storagePath);
  }

  /// 一覧用の小さな画像のパス。大きな画像のパスに `.thumb.jpg` を付ける。
  static String thumbnailPath(String path) => '$path.thumb.jpg';

  Future<void> _uploadThumbnail(String storagePath, File file) async {
    try {
      final thumb = await compressTicketThumbnailForUpload(file);
      if (thumb == null) return;
      await _client.storage
          .from(bucket)
          .upload(thumbnailPath(storagePath), thumb)
          .timeout(_uploadTimeout);
    } catch (e) {
      debugPrint('Thumbnail upload failed for $storagePath: $e');
    }
  }

  /// [uploadTicketImage] で上げた画像を消す。このバケットの URL でないものは無視する。
  Future<void> deleteTicketImages(List<String> urls) async {
    final paths = [
      for (final url in urls)
        if (ticketImageStoragePath(url) case final path?) ...[
          path,
          thumbnailPath(path),
        ],
    ];
    if (paths.isEmpty) return;
    await _client.storage.from(bucket).remove(paths);
  }

  /// 保存している URL（`.../object/public/ticket-images/<path>`）からバケット内のパスを取り出す。
  static String? ticketImageStoragePath(String url) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    final index = segments.indexOf(bucket);
    if (index < 1 || segments[index - 1] != 'public') return null;
    final path = segments.sublist(index + 1).join('/');
    return path.isEmpty ? null : path;
  }

  /// 保存している画像の URL を、表示のために取得する URL とヘッダーにする。
  ///
  /// このバケットの画像はログイン中のユーザーのトークンを付けて認証つきの窓口から取る。
  /// それ以外の URL はそのまま返し、[storage] にも触れない（Supabase を初期化していないテストでも使える）。
  static ({String url, Map<String, String>? headers}) ticketImageRequest(
    String storedUrl, {
    SupabaseStorageClient? storage,
  }) {
    final path = ticketImageStoragePath(storedUrl);
    if (path == null) return (url: storedUrl, headers: null);
    final client = storage ?? Supabase.instance.client.storage;
    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    return (
      url: '${client.url}/object/authenticated/$bucket/$encodedPath',
      headers: Map.unmodifiable(client.headers),
    );
  }

  /// 画像の取得先を、先に試す順に返す。
  ///
  /// [thumbnail] が true なら、一覧用の小さな画像を先に試す（古い記録には無いので、
  /// 取れなければ大きな画像に切り替わる）。最後に、認証なしの公開 URL も試す。
  static ({NetworkImageSource primary, List<NetworkImageSource> alternatives})
  ticketImageSources(
    String storedUrl, {
    bool thumbnail = false,
    SupabaseStorageClient? storage,
  }) {
    NetworkImageSource sourceOf(String url) {
      final request = ticketImageRequest(url, storage: storage);
      return NetworkImageSource(request.url, headers: request.headers);
    }

    final full = sourceOf(storedUrl);
    final isBucketImage = ticketImageStoragePath(storedUrl) != null;
    final publicFull = isBucketImage ? NetworkImageSource(storedUrl) : null;
    if (!isBucketImage) return (primary: full, alternatives: const []);
    if (thumbnail) {
      return (
        primary: sourceOf('$storedUrl.thumb.jpg'),
        alternatives: [full, ?publicFull],
      );
    }
    return (primary: full, alternatives: [?publicFull]);
  }
}
