import 'package:recolle/features/records/models/record.dart';

/// 記録を「これから」と「これまで」に分ける。
///
/// 当日の公演は、終演時刻がわからないので日付が変わるまで「これから」に残す。
/// これからは近い順、これまでは新しい順に並べる。
({List<Record> upcoming, List<Record> past}) splitByDate(
  Iterable<Record> records,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final upcoming = <Record>[];
  final past = <Record>[];
  for (final r in records) {
    final day = DateTime(r.date.year, r.date.month, r.date.day);
    (day.isBefore(today) ? past : upcoming).add(r);
  }
  upcoming.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  past.sort((a, b) => b.startsAt.compareTo(a.startsAt));
  return (upcoming: upcoming, past: past);
}

/// カウントダウンの表示内容。
sealed class Countdown {
  const Countdown();

  factory Countdown.between(Record record, DateTime now) {
    final remaining = record.startsAt.difference(now);
    final today = DateTime(now.year, now.month, now.day);
    final isToday =
        DateTime(record.date.year, record.date.month, record.date.day) == today;
    if (isToday && (record.startTime == null || remaining.isNegative)) {
      return const CountdownToday();
    }
    if (remaining.isNegative) return const CountdownToday();
    return CountdownRemaining(
      days: remaining.inDays,
      clock: _formatClock(remaining - Duration(days: remaining.inDays)),
    );
  }
}

/// 当日（開演時刻が未入力、または開演を過ぎた）。
class CountdownToday extends Countdown {
  const CountdownToday();
}

/// 開演まで [days] 日と [clock]（"HH:MM:SS"）。
class CountdownRemaining extends Countdown {
  const CountdownRemaining({required this.days, required this.clock});

  final int days;
  final String clock;
}

String _formatClock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}
