import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/utils/yen_format.dart';
import 'package:recolle/features/records/models/record.dart';

void main() {
  group('ClockTime', () {
    test('DB の time 型と "18:00" を読み、"HH:mm" で書き出す', () {
      expect(ClockTime.tryParse('18:30:00'), const ClockTime(18, 30));
      expect(ClockTime.tryParse('9:05'), const ClockTime(9, 5));
      expect(const ClockTime(9, 5).format(), '09:05');
    });

    test('形式や範囲が不正なら null', () {
      expect(ClockTime.tryParse(null), isNull);
      expect(ClockTime.tryParse('夕方'), isNull);
      expect(ClockTime.tryParse('24:00'), isNull);
      expect(ClockTime.tryParse('18:60'), isNull);
    });
  });

  test('会場・座席・チケット代・開演を JSON で往復できる', () {
    final json = {
      'id': 'r1',
      'type': 'live',
      'title': 'DOME LIVE',
      'artist_or_author': 'YOASOBI',
      'date': '2026-05-03',
      'ticket_image_url': null,
      'venue': '東京ドーム',
      'seat': 'アリーナ A5',
      'ticket_price': 12800,
      'start_time': '18:00:00',
    };
    final record = Record.fromJson(json);
    expect(record.venue, '東京ドーム');
    expect(record.seat, 'アリーナ A5');
    expect(record.ticketPrice, 12800);
    expect(record.startTime, const ClockTime(18, 0));
    expect(record.startsAt, DateTime(2026, 5, 3, 18));

    final out = record.toJson();
    expect(out['venue'], '東京ドーム');
    expect(out['ticket_price'], 12800);
    expect(out['start_time'], '18:00');
  });

  test('開場・終演を JSON で往復でき、開演より前の終演は翌日とみなす', () {
    final record = Record.fromJson({
      'id': 'r1',
      'type': 'live',
      'title': 'ALL NIGHT',
      'artist_or_author': 'DJ',
      'date': '2026-05-03',
      'open_time': '21:30:00',
      'start_time': '22:00:00',
      'end_time': '05:00:00',
    });
    expect(record.opensAt, DateTime(2026, 5, 3, 21, 30));
    expect(record.endsAt, DateTime(2026, 5, 4, 5));
    expect(record.toJson()['open_time'], '21:30');
    expect(record.toJson()['end_time'], '05:00');
  });

  test('新しい項目がない古いデータも読める', () {
    final record = Record.fromJson({
      'id': 'r1',
      'type': 'movie',
      'title': 'x',
      'artist_or_author': 'y',
      'date': '2026-01-01',
    });
    expect(record.venue, isNull);
    expect(record.ticketPrice, isNull);
    expect(record.startTime, isNull);
    expect(record.opensAt, isNull);
    expect(record.endsAt, isNull);
    expect(record.startsAt, DateTime(2026));
  });

  test('formatYen は 3 桁ごとに区切る', () {
    expect(formatYen(0), '¥0');
    expect(formatYen(980), '¥980');
    expect(formatYen(12800), '¥12,800');
    expect(formatYen(1234567), '¥1,234,567');
  });
}
