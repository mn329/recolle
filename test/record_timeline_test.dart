import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_timeline.dart';
import 'package:recolle/features/records/widgets/next_event_card.dart';

Record _record(
  String id,
  DateTime date, {
  ClockTime? openTime,
  ClockTime? startTime,
  ClockTime? endTime,
}) => Record(
  id: id,
  type: RecordType.live,
  title: 'LIVE $id',
  artistOrAuthor: 'Artist',
  date: date,
  openTime: openTime,
  startTime: startTime,
  endTime: endTime,
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

  group('sortTimeline', () {
    Record live(String id, DateTime date, EventFormat format) => Record(
      id: id,
      type: RecordType.live,
      title: 'LIVE $id',
      artistOrAuthor: 'Artist',
      date: date,
      eventFormat: format,
    );
    final records = [
      live('fes-early', DateTime(2026, 10, 1), EventFormat.festival),
      live('one-late', DateTime(2026, 12, 1), EventFormat.oneman),
      live('taiban', DateTime(2026, 11, 1), EventFormat.taiban),
      live('one-early', DateTime(2026, 10, 15), EventFormat.oneman),
    ];

    test('日付の近い順・遠い順に並べ替える', () {
      expect(
        sortTimeline(
          records,
          TimelineSort.dateAscending,
          upcoming: true,
        ).map((r) => r.id),
        ['fes-early', 'one-early', 'taiban', 'one-late'],
      );
      expect(
        sortTimeline(
          records,
          TimelineSort.dateDescending,
          upcoming: true,
        ).map((r) => r.id),
        ['one-late', 'taiban', 'one-early', 'fes-early'],
      );
    });

    test('ライブ形態順は形態ごとにまとめ、中は区分の既定の日付順にする', () {
      final upcoming = sortTimeline(
        records,
        TimelineSort.eventFormat,
        upcoming: true,
      );
      expect(upcoming.map((r) => r.id), [
        'one-early',
        'one-late',
        'taiban',
        'fes-early',
      ]);
      expect(
        sortTimeline(
          records,
          TimelineSort.eventFormat,
          upcoming: false,
        ).map((r) => r.id),
        ['one-late', 'one-early', 'taiban', 'fes-early'],
      );
      expect(
        groupByEventFormat(upcoming).map((g) => (g.format, g.records.length)),
        [
          (EventFormat.oneman, 2),
          (EventFormat.taiban, 1),
          (EventFormat.festival, 1),
        ],
      );
    });

    test('ライブ形態順を選べるのはライブだけ', () {
      expect(
        TimelineSort.optionsFor(RecordType.live),
        contains(TimelineSort.eventFormat),
      );
      expect(
        TimelineSort.optionsFor(RecordType.movie),
        isNot(contains(TimelineSort.eventFormat)),
      );
    });
  });

  test('終演時刻があれば、終演した時点で「これまで」へ移す', () {
    final result = splitByDate([
      _record('ended', DateTime(2026, 9, 27), endTime: const ClockTime(14, 0)),
      _record(
        'playing',
        DateTime(2026, 9, 27),
        endTime: const ClockTime(16, 0),
      ),
      // 前日 22:00 開演・翌 5:00 終演のオールナイトは、翌日の終演まで「これから」
      _record(
        'all-night',
        DateTime(2026, 9, 26),
        startTime: const ClockTime(22, 0),
        endTime: const ClockTime(5, 0),
      ),
    ], now);

    expect(result.upcoming.map((r) => r.id), ['playing']);
    expect(result.past.map((r) => r.id), ['ended', 'all-night']);

    final early = splitByDate([
      _record(
        'all-night',
        DateTime(2026, 9, 26),
        startTime: const ClockTime(22, 0),
        endTime: const ClockTime(5, 0),
      ),
    ], DateTime(2026, 9, 27, 4, 0));
    expect(early.upcoming, hasLength(1));
  });

  test('開場・開演・終演の時刻を 1 行にまとめる', () {
    expect(
      formatEventTimes(
        _record(
          'a',
          DateTime(2026, 9, 27),
          openTime: const ClockTime(17, 0),
          startTime: const ClockTime(18, 0),
          endTime: const ClockTime(20, 30),
        ),
      ),
      '17:00 開場・18:00 開演・20:30 終演',
    );
    expect(formatEventTimes(_record('b', DateTime(2026, 9, 27))), isNull);
  });

  group('Countdown', () {
    final show = _record(
      'show',
      DateTime(2026, 9, 27),
      openTime: const ClockTime(17, 0),
      startTime: const ClockTime(18, 0),
      endTime: const ClockTime(20, 30),
    );

    CountdownRemaining remainingAt(int hour, int minute) =>
        Countdown.between(show, DateTime(2026, 9, 27, hour, minute))
            as CountdownRemaining;

    test('開場前は開場まで、開場後は開演まで、開演後は終演までを数える', () {
      expect(remainingAt(16, 0).target, CountdownTarget.open);
      expect(remainingAt(16, 0).clock, '01:00:00');
      expect(remainingAt(17, 30).target, CountdownTarget.start);
      expect(remainingAt(17, 30).clock, '00:30:00');
      expect(remainingAt(19, 0).target, CountdownTarget.end);
      expect(remainingAt(19, 0).clock, '01:30:00');
    });

    test('終演を過ぎたら「終演」', () {
      expect(
        Countdown.between(show, DateTime(2026, 9, 27, 21, 0)),
        isA<CountdownEnded>(),
      );
    });

    test('前日以前は開場までの日数を出す', () {
      final c = Countdown.between(show, DateTime(2026, 9, 25, 17, 0));
      c as CountdownRemaining;
      expect(c.target, CountdownTarget.open);
      expect(c.days, 2);
      expect(c.clock, '00:00:00');
    });

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

    test('前日の夜で残りが 24 時間を切っていても、当日扱いにはしない', () {
      final c =
          Countdown.between(
                _record(
                  'a',
                  DateTime(2026, 9, 28),
                  startTime: const ClockTime(12, 0),
                ),
                now,
              )
              as CountdownRemaining;
      expect(c.days, 0);
      expect(c.clock, '21:00:00');
    });
  });

  Future<void> pumpCard(WidgetTester tester, Record record) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: NextEventCard(record: record, clock: () => now),
          ),
        ),
      );

  testWidgets('当日で開演時刻があれば、日数を出さず残り時間だけを出す', (tester) async {
    await pumpCard(
      tester,
      _record('a', DateTime(2026, 9, 27), startTime: const ClockTime(18, 0)),
    );
    expect(find.text('日'), findsNothing);
    expect(find.text('03:00:00'), findsOneWidget);
  });

  testWidgets('当日で開演時刻が未入力でも「0日」と出す', (tester) async {
    await pumpCard(tester, _record('a', DateTime(2026, 9, 27)));
    expect(find.text('0'), findsOneWidget);
    expect(find.text('日'), findsOneWidget);
  });

  testWidgets('前日の夜は日数を出さず、残り時間だけを出す', (tester) async {
    await pumpCard(
      tester,
      _record('a', DateTime(2026, 9, 28), startTime: const ClockTime(12, 0)),
    );
    expect(find.text('日'), findsNothing);
    expect(find.text('21:00:00'), findsOneWidget);
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
    expect(find.text('次の公演・開演まで'), findsOneWidget);

    current = current.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('02:59:59'), findsOneWidget);
  });

  testWidgets('開演後は「公演中・終演まで」に切り替わる', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NextEventCard(
            record: _record(
              'a',
              DateTime(2026, 9, 27),
              openTime: const ClockTime(13, 0),
              startTime: const ClockTime(14, 0),
              endTime: const ClockTime(16, 0),
            ),
            clock: () => now,
          ),
        ),
      ),
    );
    expect(find.text('公演中・終演まで'), findsOneWidget);
    expect(find.text('01:00:00'), findsOneWidget);
    expect(find.textContaining('13:00 開場・14:00 開演・16:00 終演'), findsOneWidget);
  });
}
