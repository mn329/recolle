import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_timeline.dart';
import 'package:recolle/features/records/widgets/next_event_card.dart';

Record _record(String id, DateTime date, {ClockTime? startTime}) => Record(
  id: id,
  type: RecordType.live,
  title: 'LIVE $id',
  artistOrAuthor: 'Artist',
  date: date,
  ticketImageUrl: '',
  startTime: startTime,
);

void main() {
  final now = DateTime(2026, 9, 27, 15, 0);

  test('今日以降は「これから」を近い順、過去は新しい順に分ける', () {
    final result = splitByDate([
      _record('past-old', DateTime(2026, 1, 1)),
      _record('future-far', DateTime(2026, 12, 24)),
      _record('today', DateTime(2026, 9, 27)),
      _record('past-new', DateTime(2026, 9, 26)),
      _record('future-near', DateTime(2026, 10, 1)),
    ], now);

    expect(result.upcoming.map((r) => r.id), [
      'today',
      'future-near',
      'future-far',
    ]);
    expect(result.past.map((r) => r.id), ['past-new', 'past-old']);
  });

  group('Countdown', () {
    test('開演までの日数と時分秒を出す', () {
      final c = Countdown.between(
        _record('a', DateTime(2026, 9, 29), startTime: const ClockTime(18, 30)),
        now,
      );
      expect(c, isA<CountdownRemaining>());
      c as CountdownRemaining;
      expect(c.days, 2);
      expect(c.clock, '03:30:00');
    });

    test('当日で開演時刻が未入力なら「今日」', () {
      expect(
        Countdown.between(_record('a', DateTime(2026, 9, 27)), now),
        isA<CountdownToday>(),
      );
    });

    test('当日で開演を過ぎたら「今日」', () {
      expect(
        Countdown.between(
          _record(
            'a',
            DateTime(2026, 9, 27),
            startTime: const ClockTime(13, 0),
          ),
          now,
        ),
        isA<CountdownToday>(),
      );
    });

    test('当日の開演前は残り時間だけを出す', () {
      final c =
          Countdown.between(
                _record(
                  'a',
                  DateTime(2026, 9, 27),
                  startTime: const ClockTime(18, 0),
                ),
                now,
              )
              as CountdownRemaining;
      expect(c.days, 0);
      expect(c.clock, '03:00:00');
    });
  });

  testWidgets('カウントダウンは 1 秒ごとに進む', (tester) async {
    var current = now;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NextEventCard(
            record: _record(
              'a',
              DateTime(2026, 9, 27),
              startTime: const ClockTime(18, 0),
            ),
            clock: () => current,
          ),
        ),
      ),
    );
    expect(find.text('03:00:00'), findsOneWidget);

    current = current.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('02:59:59'), findsOneWidget);
  });
}
