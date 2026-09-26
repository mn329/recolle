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
