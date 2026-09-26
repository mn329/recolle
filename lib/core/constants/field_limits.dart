/// 入力欄の最大文字数（アプリ・DB の目安を揃える）。
abstract final class RecordFieldLimits {
  RecordFieldLimits._();

  static const int title = 300;
  static const int artistOrAuthor = 300;
  static const int ticketSource = 80;
  /// セットリストを改行で結合したときの合計。
  static const int setlistTotal = 10000;
  static const int setlistSongLine = 200;
  static const int mcMemo = 2000;
  static const int impressions = 4000;
}
