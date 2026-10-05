import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// チケット画像を端末に保存して使い回す。
///
/// メモリだけのキャッシュだと、アプリを開き直すたびに全部ダウンロードし直すことになる。
/// 端末にも 30 日分を保存し、2 回目以降はダウンロードなしで表示する。
final CacheManager ticketImageCacheManager = CacheManager(
  Config(
    'ticket_images',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 400,
  ),
);

/// [ticketImageCacheManager] 経由で画像を読む [ImageProvider]。
///
/// 保存の鍵は URL だけ（認証のヘッダーは含めない）。取得に失敗した画像は保存されない。
@immutable
class ManagedNetworkImage extends ImageProvider<ManagedNetworkImage> {
  const ManagedNetworkImage(this.url, {this.headers, this.scale = 1.0});

  final String url;

  /// 取得時に付ける HTTP ヘッダー（非公開の画像に付ける認証など）。
  final Map<String, String>? headers;
  final double scale;

  @override
  Future<ManagedNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ManagedNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(
    ManagedNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => [DiagnosticsProperty('URL', key.url)],
    );
  }

  Future<ui.Codec> _load(
    ManagedNetworkImage key,
    ImageDecoderCallback decode,
  ) async {
    final file = await ticketImageCacheManager.getSingleFile(
      key.url,
      headers: key.headers ?? const {},
    );
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      await ticketImageCacheManager.removeFile(key.url);
      throw StateError('Empty image file: ${key.url}');
    }
    try {
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      // 壊れた保存ファイルは捨てて、次回は取り直す
      await ticketImageCacheManager.removeFile(key.url);
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ManagedNetworkImage && other.url == url && other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() => 'ManagedNetworkImage("$url", scale: $scale)';
}
