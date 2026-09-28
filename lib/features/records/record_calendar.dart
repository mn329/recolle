import 'package:recolle/features/records/models/record.dart';

/// 日付だけ（時刻 0:00）にそろえる。
DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// 日ごとの記録。複数日の公演は期間中の毎日に入れる。同じ日の中は開演の早い順。
Map<DateTime, List<Record>> recordsByDay(Iterable<Record> records) {
  final map = <DateTime, List<Record>>{};
  for (final r in records) {
    final last = dayOf(r.lastDate);
    for (
      var day = dayOf(r.date);
      !day.isAfter(last);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      map.putIfAbsent(day, () => []).add(r);
    }
  }
  for (final list in map.values) {
    list.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }
  return map;
}

/// 日曜始まりの月のマス目。前後の月の分は null で埋め、7 の倍数の長さにする。
List<DateTime?> monthGrid(int year, int month) {
  final first = DateTime(year, month);
  final daysInMonth = DateTime(year, month + 1, 0).day;
  // DateTime.weekday は月曜 1〜日曜 7。日曜始まりの列番号にする
  final leading = first.weekday % 7;
  final cells = <DateTime?>[
    for (var i = 0; i < leading; i++) null,
    for (var d = 1; d <= daysInMonth; d++) DateTime(year, month, d),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return cells;
}
