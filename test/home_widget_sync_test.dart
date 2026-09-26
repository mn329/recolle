import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/records/home_widget_sync.dart';
import 'package:recolle/features/records/models/record.dart';

Record _record(
  String id,
  DateTime date, {
  RecordType type = RecordType.live,
  ClockTime? startTime,
  String? venue,
}) => Record(
  id: id,
  type: type,
  title: 'LIVE $id',
  artistOrAuthor: 'Artist',
  date: date,
  ticketImageUrl: '',
  startTime: startTime,
  venue: venue,
);

void main() {
  final now = DateTime(2026, 9, 27, 12);

  test('これからの記録だけを近い順に、最大 5 件渡す', () {
    final records = [
      _record('past', DateTime(2026, 9, 1)),
      for (var i = 7; i >= 1; i--) _record('$i', DateTime(2026, 10, i)),
    ];

    final payload = upcomingEventsPayload(records, now);

    expect(payload.map((e) => e['title']), [
      'LIVE 1',
      'LIVE 2',
      'LIVE 3',
      'LIVE 4',
      'LIVE 5',
    ]);
  });

  test('開演時刻・会場・種別をウィジェット用の値にする', () {
    final payload = upcomingEventsPayload([
      _record(
        'a',
        DateTime(2026, 10, 3),
        startTime: const ClockTime(18, 30),
        venue: '日本武道館',
      ),
      _record('b', DateTime(2026, 10, 4), type: RecordType.movie),
    ], now);

    expect(payload[0], {
      'title': 'LIVE a',
      'artist': 'Artist',
      'startsAt': DateTime(2026, 10, 3, 18, 30).millisecondsSinceEpoch,
      'hasStartTime': true,
      'venue': '日本武道館',
      'isLive': true,
    });
    expect(payload[1]['hasStartTime'], false);
    expect(payload[1]['venue'], isNull);
    expect(payload[1]['isLive'], false);
  });

  test('当日の公演は開演後も「これから」に含める', () {
    final payload = upcomingEventsPayload([
      _record(
        'today',
        DateTime(2026, 9, 27),
        startTime: const ClockTime(10, 0),
      ),
    ], now);

    expect(payload, hasLength(1));
  });
}
