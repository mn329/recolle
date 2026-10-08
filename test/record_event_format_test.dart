import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/utils/japanese_date_format.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_calendar.dart';
import 'package:recolle/features/records/record_stats.dart';
import 'package:recolle/features/records/record_timeline.dart';
import 'package:recolle/features/search/search_logic.dart';

Record _record({
  String id = 'r',
  String artist = 'YOASOBI',
  String? setlist,
  DateTime? date,
  DateTime? endDate,
  EventFormat format = EventFormat.oneman,
  List<RecordAct> acts = const [],
  ClockTime? startTime,
  ClockTime? endTime,
}) => Record(
  id: id,
  type: RecordType.live,
  title: 'SHOW',
  artistOrAuthor: acts.isEmpty ? artist : Record.headlineFor(acts),
  date: date ?? DateTime(2026, 8, 1),
  setlist: setlist,
  eventFormat: format,
  endDate: endDate,
  acts: acts,
  startTime: startTime,
  endTime: endTime,
);

const _taibanActs = [
  RecordAct(artist: 'sumika', songs: ['Lovers', 'ファンファーレ']),
  RecordAct(artist: 'Mrs. GREEN APPLE', songs: ['ケセラセラ'], isMain: true),
];

void main() {
  group('Record の出演者', () {
    test('JSON を往復しても形式・最終日・出演者ごとのセトリを保つ', () {
      final record = _record(
        format: EventFormat.festival,
        endDate: DateTime(2026, 8, 2),
        acts: _taibanActs,
      );
      final json = {...record.toJson(), 'id': 'r'};

      final restored = Record.fromJson(json);

      expect(json['event_format'], 'festival');
      expect(restored.eventFormat, EventFormat.festival);
      expect(restored.endDate, DateTime(2026, 8, 2));
      expect(restored.acts, _taibanActs);
    });

    test('複数日のフェスでは出演した日も往復する', () {
      final acts = [
        const RecordAct(artist: 'サカナクション', day: 1),
        const RecordAct(artist: 'sumika', day: 2),
      ];
      final record = _record(
        format: EventFormat.festival,
        date: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 3),
        acts: acts,
      );

      final restored = Record.fromJson({...record.toJson(), 'id': 'r'});

      expect(restored.acts, acts);
      expect(restored.dayCount, 3);
      expect(Record.dayCountBetween(DateTime(2026, 8, 1), null), 1);
    });

    test('形式や出演者のない従来の記録はワンマンとして読む', () {
      final restored = Record.fromJson({
        'id': 'old',
        'type': 'live',
        'title': 'TOUR',
        'artist_or_author': 'YOASOBI',
        'date': '2026-08-01',
        'setlist': 'アイドル\n祝福',
      });

      expect(restored.eventFormat, EventFormat.oneman);
      expect(restored.endDate, isNull);
      expect(restored.acts, isEmpty);
      expect(restored.performances.single.songs, ['アイドル', '祝福']);
    });

    test('対バンは出演者それぞれで当たり、曲はその出演者の分だけ返す', () {
      final record = _record(format: EventFormat.taiban, acts: _taibanActs);

      expect(record.features('SUMIKA'), isTrue);
      expect(record.features('Mrs. GREEN APPLE'), isTrue);
      expect(record.features('YOASOBI'), isFalse);
      expect(record.songsBy('sumika'), ['Lovers', 'ファンファーレ']);
      expect(record.songsBy('Mrs. GREEN APPLE'), ['ケセラセラ']);
    });

    test('見出しはお目当てを優先し、いなければ全員を並べる', () {
      expect(Record.headlineFor(_taibanActs), 'Mrs. GREEN APPLE');
      expect(
        Record.headlineFor([
          for (final a in _taibanActs) a.copyWith(isMain: false),
        ]),
        'sumika ／ Mrs. GREEN APPLE',
      );
    });

    test('見出しが長すぎるときは入る分だけにして「ほか」を付ける', () {
      final acts = [
        for (var i = 0; i < 40; i++) RecordAct(artist: 'ARTIST NAME $i'),
      ];

      final headline = Record.headlineFor(acts);

      expect(headline.length, lessThanOrEqualTo(Record.headlineMaxLength));
      expect(headline, startsWith('ARTIST NAME 0 ／ ARTIST NAME 1'));
      expect(headline, endsWith(' ほか'));
    });
  });

  group('複数日の公演', () {
    final fes = _record(
      format: EventFormat.festival,
      date: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 2),
      startTime: const ClockTime(10, 0),
      endTime: const ClockTime(21, 0),
      acts: _taibanActs,
    );

    test('終演は最終日の時刻で、初日の夜はまだ「これから」に残る', () {
      expect(fes.endsAt, DateTime(2026, 8, 2, 21));
      expect(splitByDate([fes], DateTime(2026, 8, 1, 22)).upcoming, [fes]);
      expect(splitByDate([fes], DateTime(2026, 8, 2, 22)).past, [fes]);
    });

    test('終演時刻がなければ最終日のうちは「これから」', () {
      final noTime = _record(
        date: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 2),
      );
      expect(splitByDate([noTime], DateTime(2026, 8, 2, 23)).upcoming, [
        noTime,
      ]);
      expect(splitByDate([noTime], DateTime(2026, 8, 3)).past, [noTime]);
    });

    test('カレンダーでは期間中の毎日に出す', () {
      final byDay = recordsByDay([fes]);
      expect(byDay.keys, [DateTime(2026, 8, 1), DateTime(2026, 8, 2)]);
    });

    test('期間は年が同じなら終わりの年を省く', () {
      expect(
        formatJapaneseDateRange(
          DateTime(2026, 8, 1),
          DateTime(2026, 8, 2),
          includeWeekday: true,
        ),
        '2026年8月1日 (土)〜8月2日 (日)',
      );
      expect(
        formatJapaneseDateRange(DateTime(2026, 12, 31), DateTime(2027, 1, 1)),
        '2026年12月31日〜2027年1月1日',
      );
      expect(formatJapaneseDateRange(DateTime(2026, 8, 1), null), '2026年8月1日');
    });
  });

  group('集計と検索', () {
    final now = DateTime(2026, 9, 1);
    final records = [
      _record(
        id: 'oneman',
        artist: 'Mrs. GREEN APPLE',
        setlist: 'ケセラセラ',
        date: DateTime(2026, 6, 1),
      ),
      _record(id: 'taiban', format: EventFormat.taiban, acts: _taibanActs),
    ];

    test('対バンの出演者全員を「観たアーティスト」として数え、曲も数える', () {
      final stats = computeStats(records, now: now);

      expect(stats.topArtists, [
        (label: 'Mrs. GREEN APPLE', count: 2),
        (label: 'sumika', count: 1),
      ]);
      expect(stats.topSongs.first, (
        title: 'ケセラセラ',
        artist: 'Mrs. GREEN APPLE',
        count: 2,
      ));
      expect(filterByArtist(records, 'sumika').map((r) => r.id), ['taiban']);
    });

    test('出演者も曲もアーティスト検索・曲検索に出る', () {
      final artists = searchLocalArtists(
        records: records,
        favorites: const [],
        query: '',
      );
      expect(
        {for (final a in artists) a.name: a.recordCount},
        {'Mrs. GREEN APPLE': 2, 'sumika': 1},
      );

      final songs = searchLocalSongs(records, 'Lovers');
      expect(songs.single.artistName, 'sumika');

      final hits = searchRecords(records, 'ファンファーレ');
      expect(hits.single.record.id, 'taiban');
      expect(hits.single.matchLabel, 'セトリ');
    });
  });
}
