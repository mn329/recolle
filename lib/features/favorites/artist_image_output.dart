import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// アップロードするアーティスト画像の一辺の上限（px）と JPEG 品質。
/// 一覧のカードや詳細の見出しに出すだけなので、チケット画像よりずっと小さくてよい。
const artistImageMaxSide = 800;
const artistImageQuality = 80;

/// 切り抜いた画像 [cropped] を、上限の大きさの JPEG にして一時ファイルに書き出す。
Future<File> saveArtistImageAsJpeg(Uint8List cropped) async {
  final jpeg = await FlutterImageCompress.compressWithList(
    cropped,
    minWidth: artistImageMaxSide,
    minHeight: artistImageMaxSide,
    quality: artistImageQuality,
    format: CompressFormat.jpeg,
  );
  final tmp = await getTemporaryDirectory();
  return File(
    p.join(tmp.path, 'artist_${DateTime.now().microsecondsSinceEpoch}.jpg'),
  ).writeAsBytes(jpeg);
}
