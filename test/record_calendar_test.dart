import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_calendar.dart';
import 'package:recolle/features/records/widgets/record_calendar_view.dart';

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
  test('日曜始まりで前後の空きを null で埋める', () {
    // 2026年9月1日は火曜
    final grid = monthGrid(2026, 9);
    expect(grid.length % 7, 0);
    expect(grid.take(2), [null, null]);
    expect(grid[2], DateTime(2026, 9, 1));
    expect(grid.whereType<DateTime>().length, 30);
  });

  test('日ごとにまとめ、同じ日は開演の早い順に並べる', () {
    final map = recordsByDay([
      _record('late', DateTime(2026, 9, 1), startTime: const ClockTime(19, 0)),
      _record('early', DateTime(2026, 9, 1), startTime: const ClockTime(13, 0)),
      _record('other', DateTime(2026, 9, 2)),
    ]);
    expect(map[DateTime(2026, 9, 1)]!.map((r) => r.id), ['early', 'late']);
    expect(map[DateTime(2026, 9, 2)]!.length, 1);
  });

  testWidgets('日を選ぶとその日の記録を表示し、月を送れる', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecordCalendarView(
              today: DateTime(2026, 9, 27),
              records: [
                _record('a', DateTime(2026, 9, 5)),
                _record('b', DateTime(2026, 10, 10)),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('2026年9月'), findsOneWidget);
    expect(find.text('この日の記録はありません'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('9月5日、記録1件'));
    await tester.pump();
    expect(find.text('LIVE a'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('次の月'));
    await tester.pump();
    expect(find.text('2026年10月'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('10月10日、記録1件'));
    await tester.pump();
    expect(find.text('LIVE b'), findsOneWidget);
  });
}
