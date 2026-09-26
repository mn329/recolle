import 'package:recolle/features/records/models/record.dart';

/// 記録を「これから」と「これまで」に分ける。
///
/// 終演時刻があれば終演した時点で「これまで」へ移す。なければ当日のうちは「これから」に残す。
/// これからは近い順、これまでは新しい順に並べる。
({List<Record> upcoming, List<Record> past}) splitByDate(
  Iterable<Record> records,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final upcoming = <Record>[];
  final past = <Record>[];
  for (final r in records) {
    final endsAt = r.endsAt;
    final isPast = endsAt != null
        ? !endsAt.isAfter(now)
        : DateTime(r.date.year, r.date.month, r.date.day).isBefore(today);
    (isPast ? past : upcoming).add(r);
  }
  upcoming.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  past.sort((a, b) => b.startsAt.compareTo(a.startsAt));
  return (upcoming: upcoming, past: past);
}

/// カウントダウンの行き先。
enum CountdownTarget {
  open,
  start,
  end;

  /// 種別ごとの呼び方（ライブなら開場・開演・終演、映画なら上映開始・上映終了）。
  String labelFor(RecordType type) => switch (this) {
    CountdownTarget.open => '開場',
    CountdownTarget.start => type.startTimeLabel,
    CountdownTarget.end => type.endTimeLabel,
  };
}

/// カウントダウンの表示内容。
sealed class Countdown {
  const Countdown();

  /// 開場 → 開演 → 終演の順に、まだ来ていない最初の時刻までを数える。
  factory Countdown.between(Record record, DateTime now) {
    final targets = [
      if (record.opensAt case final at?) (CountdownTarget.open, at),
      (CountdownTarget.start, record.startsAt),
      if (record.endsAt case final at?) (CountdownTarget.end, at),
    ];
    for (final (target, at) in targets) {
      final remaining = at.difference(now);
      if (remaining <= Duration.zero) continue;
      return CountdownRemaining(
        target: target,
        // 開演時刻が未入力なら当日 0 時までを数えているだけで、当日になれば「今日」になる
        hasTime: target != CountdownTarget.start || record.startTime != null,
        days: remaining.inDays,
        clock: _formatClock(remaining - Duration(days: remaining.inDays)),
      );
    }
    return record.endsAt != null
        ? const CountdownEnded()
        : const CountdownToday();
  }
}

/// 当日（開演時刻が未入力、または開演を過ぎて終演時刻が未入力）。
class CountdownToday extends Countdown {
  const CountdownToday();
}

/// 終演した。
class CountdownEnded extends Countdown {
  const CountdownEnded();
}

/// [target] まで [days] 日と [clock]（"HH:MM:SS"）。
///
/// [hasTime] が false のときは時刻が未入力で、当日 0 時までを数えている。
class CountdownRemaining extends Countdown {
  const CountdownRemaining({
    required this.target,
    required this.hasTime,
    required this.days,
    required this.clock,
  });

  final CountdownTarget target;
  final bool hasTime;
  final int days;
  final String clock;
}

/// 「17:00 開場・18:00 開演・20:30 終演」の形。時刻が 1 つもなければ null。
String? formatEventTimes(Record record) {
  final type = record.type;
  final parts = [
    for (final (target, time) in [
      (CountdownTarget.open, record.openTime),
      (CountdownTarget.start, record.startTime),
      (CountdownTarget.end, record.endTime),
    ])
      if (time != null) '${time.format()} ${target.labelFor(type)}',
  ];
  return parts.isEmpty ? null : parts.join('・');
}

String _formatClock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}
