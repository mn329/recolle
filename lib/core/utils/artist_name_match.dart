/// 表記ゆれ（大文字小文字・全角半角スペース）を吸収した比較用キー。
String normalizeArtistName(String name) {
  return name.toLowerCase().replaceAll(RegExp(r'[\s\u3000]+'), '');
}

/// 対バン・コラボ表記（「A × B」「A & B」「A feat. B」など）の区切り。
final _collaborationSeparator = RegExp(
  r'\s*(?:×|✕|&|＆|,|、|/|／|\bfeat\.?|\bft\.|\bwith\b|\bvs\.?)\s*',
  caseSensitive: false,
);

/// 記録のアーティスト欄 [recordArtist] が、お気に入り [favoriteName] を含むか。
///
/// 部分一致だと短い名前（例: "A"）が無関係な記録に当たるため、
/// 全体一致か、コラボ表記を分割した各要素との一致だけを見る。
bool artistMatches(String recordArtist, String favoriteName) {
  final target = normalizeArtistName(favoriteName);
  if (target.isEmpty) return false;
  if (normalizeArtistName(recordArtist) == target) return true;
  return recordArtist
      .split(_collaborationSeparator)
      .any((part) => normalizeArtistName(part) == target);
}
