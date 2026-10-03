import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/records/field_suggestions.dart';
import 'package:recolle/features/records/models/record.dart';

Record _record(
  String id, {
  RecordType type = RecordType.live,
  String? venue,
  String? source,
}) => Record(
  id: id,
  type: type,
  title: 'T$id',
  artistOrAuthor: 'A',
  date: DateTime(2026, 1, 1),
  venue: venue,
  ticketSource: source,
);

void main() {
  group('venueSuggestions', () {
    test('過去に使った会場をよく使う順に出し、定番の会場を続ける', () {
      final result = venueSuggestions(
        records: [
          _record('1', venue: 'Zepp Shinjuku'),
          _record('2', venue: '日本武道館'),
          _record('3', venue: '日本 武道館'),
          _record('4', type: RecordType.movie, venue: 'TOHOシネマズ 新宿'),
        ],
        type: RecordType.live,
        query: '',
      );

      expect(result.take(2), ['日本武道館', 'Zepp Shinjuku']);
      expect(result, contains('東京ドーム'));
      // ほかの種別の会場や、表記ゆれの重複は出さない
      expect(result, isNot(contains('TOHOシネマズ 新宿')));
      expect(result.where((v) => v.contains('武道館')), hasLength(1));
    });

    test('入力中の文字を含む候補だけを出し、入力済みの値そのものは出さない', () {
      final records = [_record('1', venue: 'Zepp Shinjuku')];

      expect(
        venueSuggestions(
          records: records,
          type: RecordType.live,
          query: 'zepp',
        ),
        ['Zepp Shinjuku', 'Zepp Haneda', 'Zepp DiverCity'],
      );
      expect(
        venueSuggestions(
          records: records,
          type: RecordType.live,
          query: 'Zepp Shinjuku',
        ),
        isEmpty,
      );
    });

    test('ライブ以外は過去の記録の会場だけを出す', () {
      expect(
        venueSuggestions(records: const [], type: RecordType.movie, query: ''),
        isEmpty,
      );
    });
  });

  group('sourceSuggestions', () {
    test('ライブはよく使う取得元に、チケットサイトなどの定番を続ける', () {
      final result = sourceSuggestions(
        records: [_record('1', source: 'FC先行')],
        type: RecordType.live,
        query: '',
        limit: 20,
      );

      expect(result.first, 'FC先行');
      expect(result, containsAll(['e+', 'ローチケ', 'チケットぴあ', 'ファンクラブ']));
    });

    test('本は購入先の定番を出す', () {
      expect(
        sourceSuggestions(records: const [], type: RecordType.book, query: ''),
        containsAll(['書店', '電子書籍']),
      );
    });
  });
}
