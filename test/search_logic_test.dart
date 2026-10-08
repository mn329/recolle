import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/search/search_logic.dart';

Record _record(
  String id, {
  String title = 'ツアー',
  String artist = 'YOASOBI',
  RecordType type = RecordType.live,
  DateTime? date,
  String? setlist,
  String? impressions,
}) {
  return Record(
    id: id,
    type: type,
    title: title,
    artistOrAuthor: artist,
    date: date ?? DateTime(2024, 1, 1),
    setlist: setlist,
    impressions: impressions,
  );
}

void main() {
  group('searchRecords', () {
    final records = [
      _record('1', title: '武道館公演', setlist: 'アイドル\n夜に駆ける'),
      _record('2', title: 'ドーム', artist: 'Aimer', impressions: '夜に駆けるを聴けた'),
      _record('3', title: '夜に駆けるツアー', artist: 'Someone'),
    ];

    test('タイトル・アーティストでの一致を先に並べ、他の項目は当たった行を添える', () {
      final hits = searchRecords(records, '夜に駆ける');

      expect(hits.map((h) => h.record.id), ['3', '1', '2']);
      expect(hits[1].matchLabel, 'セトリ');
      expect(hits[1].snippet, '夜に駆ける');
      expect(hits[2].matchLabel, '感想');
    });

    test('空白区切りは AND 検索になり、大文字小文字を無視する', () {
      expect(searchRecords(records, 'yoasobi アイドル').map((h) => h.record.id), [
        '1',
      ]);
      expect(searchRecords(records, 'aimer アイドル'), isEmpty);
    });

    test('空の検索語では何も返さない', () {
      expect(searchRecords(records, '  '), isEmpty);
    });
  });

  test('searchLocalArtists は記録とお気に入りをまとめ、記録の多い順に並べる', () {
    final records = [
      _record('1', artist: 'YOASOBI'),
      _record('2', artist: 'yoasobi'),
      _record('3', artist: 'Aimer'),
      _record('4', artist: '村上春樹', type: RecordType.book),
    ];
    final favorites = [
      FavoriteArtist(id: 'f', name: 'milet', createdAt: DateTime(2024)),
    ];

    final all = searchLocalArtists(
      records: records,
      favorites: favorites,
      query: '',
    );

    expect(all.map((a) => (a.name, a.recordCount)), [
      ('YOASOBI', 2),
      ('Aimer', 1),
      ('milet', 0),
    ]);
    expect(all.last.favorite?.id, 'f');
    expect(
      searchLocalArtists(
        records: records,
        favorites: favorites,
        query: 'aim',
      ).map((a) => a.name),
      ['Aimer'],
    );
  });

  test('searchLocalSongs は同じ公演の重複を数えず、聴いた回数の多い順に並べる', () {
    final records = [
      _record('1', date: DateTime(2023), setlist: 'アイドル\nアイドル\n群青'),
      _record('2', date: DateTime(2024), setlist: 'アイドル'),
      _record('3', artist: 'Other', setlist: 'アイドル'),
    ];

    final songs = searchLocalSongs(records, 'アイドル');

    expect(songs.map((s) => (s.artistName, s.timesHeard)), [
      ('YOASOBI', 2),
      ('Other', 1),
    ]);
    expect(songs.first.lastHeard, DateTime(2024));
    expect(searchLocalSongs(records, '群青 yoasobi').map((s) => s.title), ['群青']);
  });
}
