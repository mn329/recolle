/// チケット画像の選択時リサイズ・JPEG 再圧縮の共通設定。
abstract final class TicketImageSettings {
  TicketImageSettings._();

  /// 1 件の記録に付けられる枚数。DB の制約 `records_ticket_image_urls_count` と揃える。
  static const int maxCount = 5;

  /// [ImagePicker.pickMultiImage] の長辺上限（px）。
  static const double maxPickDimension = 2048;

  /// ギャラリー選択時の JPEG 品質（0–100）。
  static const int pickImageQuality = 82;

  /// [FlutterImageCompress] の JPEG 品質（0–100）。
  static const int compressQuality = 78;

  /// 再圧縮時の長辺・短辺の上限（px）。縦横どちらが長くてもこのボックスに収まるよう縮小。
  static const int compressMaxEdge = 1920;

  /// 一覧のチケットに出す小さな画像の長辺（px）と JPEG 品質。大きな画像と一緒にアップロードする。
  static const int thumbnailMaxEdge = 640;
  static const int thumbnailQuality = 70;
}
