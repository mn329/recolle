/// UI 向けの和暦風（実際は「2026年04月21日」形式）日付文字列。
String formatJapaneseDate(
  DateTime d, {
  bool includeWeekday = false,
  bool padMonthDay = false,
}) {
  final month = padMonthDay
      ? d.month.toString().padLeft(2, '0')
      : d.month.toString();
  final day = padMonthDay ? d.day.toString().padLeft(2, '0') : d.day.toString();
  final base = '${d.year}年$month月$day日';
  if (!includeWeekday) return base;
  const weekDays = ['月', '火', '水', '木', '金', '土', '日'];
  final w = weekDays[d.weekday - 1];
  return '$base ($w)';
}

/// 複数日の期間。「2026年8月1日 (土)〜8月2日 (日)」の形で、年が同じなら終わりの年を省く。
/// [end] が null か [start] と同じ日なら 1 日分だけ返す。
String formatJapaneseDateRange(
  DateTime start,
  DateTime? end, {
  bool includeWeekday = false,
}) {
  final first = formatJapaneseDate(start, includeWeekday: includeWeekday);
  if (end == null ||
      (end.year == start.year &&
          end.month == start.month &&
          end.day == start.day)) {
    return first;
  }
  final last = formatJapaneseDate(end, includeWeekday: includeWeekday);
  final prefix = '${end.year}年';
  return '$first〜${end.year == start.year ? last.substring(prefix.length) : last}';
}
