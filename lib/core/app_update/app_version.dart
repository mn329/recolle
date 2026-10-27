/// `1.2.3` のようなバージョンを 3 桁の数字にする。足りない桁は 0。形式が不正なら null。
List<int>? parseAppVersion(String value) {
  final parts = value.trim().split('.');
  if (parts.length > 3) return null;
  final numbers = <int>[];
  for (final part in parts) {
    if (!RegExp(r'^\d+$').hasMatch(part)) return null;
    numbers.add(int.parse(part));
  }
  while (numbers.length < 3) {
    numbers.add(0);
  }
  return numbers;
}

/// [current] が [minimum] より古いか。どちらかが読めないときは false（止めない側に倒す）。
bool isOlderThan(String current, String minimum) {
  final c = parseAppVersion(current);
  final m = parseAppVersion(minimum);
  if (c == null || m == null) return false;
  for (var i = 0; i < 3; i++) {
    if (c[i] != m[i]) return c[i] < m[i];
  }
  return false;
}
