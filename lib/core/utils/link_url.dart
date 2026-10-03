/// 入力されたリンクを、開ける http(s) の URL にする。読めなければ null。
///
/// 「eplus.jp/...」のように先頭の https:// を省いた入力は補う。
String? parseLinkUrl(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final withScheme =
      RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(text)
      ? text
      : 'https://$text';
  final uri = Uri.tryParse(withScheme);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      !uri.host.contains('.')) {
    return null;
  }
  return uri.toString();
}
