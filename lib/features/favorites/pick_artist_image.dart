import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:recolle/features/favorites/screens/artist_image_crop_screen.dart';

/// 切り抜き前に読み込む画像の長辺の上限（px）と JPEG 品質。
/// 切り抜きの処理が重くならないよう縮めておく。最終的な大きさは切り抜きのあとに決まる。
const _maxPickDimension = 1600.0;
const _pickQuality = 90;

/// 写真ライブラリから画像を 1 枚選び、正方形に切り抜いたファイルを返す。
/// 選ばなかった・切り抜きをキャンセルしたら null。
typedef ArtistImagePicker = Future<File?> Function(BuildContext context);

/// テストで、写真ライブラリと切り抜き画面を差し替えるための口。
final artistImagePickerProvider = Provider<ArtistImagePicker>(
  (ref) => pickAndCropArtistImage,
);

Future<File?> pickAndCropArtistImage(BuildContext context) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: _maxPickDimension,
    maxHeight: _maxPickDimension,
    imageQuality: _pickQuality,
  );
  if (picked == null || !context.mounted) return null;
  return Navigator.of(context).push<File>(
    CupertinoPageRoute(
      fullscreenDialog: true,
      builder: (_) => ArtistImageCropScreen(file: File(picked.path)),
    ),
  );
}
