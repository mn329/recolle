import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/music/data/concert_discovery_client.dart';
import 'package:recolle/features/music/data/setlistfm_client.dart';
import 'package:recolle/features/records/concert_candidates.dart';
import 'package:recolle/features/records/models/record.dart';

SetlistSummary _setlist(String id, DateTime? date, {String? tour}) =>
    SetlistSummary(
      id: id,
      eventDate: date,
      artistName: 'King Gnu',
      venueName: 'Zepp Haneda',
      cityName: 'Tokyo',
      tourName: tour,
      songs: const [],
    );

Record _record(String title, DateTime date, {String artist = 'King Gnu'}) =>
    Record(
      id: title,
      type: RecordType.live,
      title: title,
      artistOrAuthor: artist,
      date: date,
      ticketImageUrl: '',
    );

void main() {
  test('今後の公演・setlist.fm・過去の記録の順に並べる', () {
    final candidates = buildConcertCandidates(
      query: '',
      artist: 'King Gnu',
      upcoming: [DiscoveredConcert(title: 'DOME', date: DateTime(2026, 11, 3))],
      setlists: [_setlist('s1', DateTime(2025, 5, 3), tour: 'ARENA')],
      records: [_record('HALL', DateTime(2024, 1, 1))],
    );

    expect(candidates.map((c) => c.source), [
      ConcertCandidateSource.upcoming,
      ConcertCandidateSource.setlistFm,
      ConcertCandidateSource.record,
    ]);
    expect(candidates.last.fillsDetails, isFalse);
  });

  test('入力で検索した setlist.fm の公演は、文字が一致しなくても直近の公演の後ろに出す', () {
    final candidates = buildConcertCandidates(
      query: 'dome',
      artist: 'King Gnu',
      setlists: [
        _setlist('s1', DateTime(2025, 5, 3), tour: 'DOME TOUR'),
        _setlist('s2', DateTime(2025, 4, 1), tour: 'ARENA'),
      ],
      searchedSetlists: [
        _setlist('s3', DateTime(2019, 12, 1), tour: 'Sympa'),
        _setlist('s1', DateTime(2025, 5, 3), tour: 'DOME TOUR'),
      ],
    );

    expect(candidates.map((c) => c.title), ['DOME TOUR', 'Sympa']);
  });

  test('ツアー名のない公演は会場名で呼び、日付のない公演は出さない', () {
    final candidates = buildConcertCandidates(
      query: '',
      artist: 'King Gnu',
      setlists: [
        _setlist('s1', DateTime(2025, 5, 3)),
        _setlist('s2', null, tour: 'NO DATE'),
      ],
    );

    expect(candidates.map((c) => c.title), ['Zepp Haneda 公演']);
  });

  test('同じ日の同じ公演は 1 件にまとめ、別のアーティストの記録は出さない', () {
    final candidates = buildConcertCandidates(
      query: '',
      artist: 'King Gnu',
      setlists: [_setlist('s1', DateTime(2025, 5, 3), tour: 'ARENA')],
      records: [
        _record('ARENA', DateTime(2025, 5, 3)),
        _record('OTHER', DateTime(2025, 6, 1), artist: 'YOASOBI'),
      ],
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.source, ConcertCandidateSource.setlistFm);
  });

  test('過去の記録は同じ公演名を 1 件にまとめ、新しい日付のものを残す', () {
    final candidates = buildConcertCandidates(
      query: 'hall',
      artist: 'King Gnu',
      records: [
        _record('HALL TOUR', DateTime(2025, 1, 10)),
        _record('HALL TOUR', DateTime(2025, 2, 1)),
        _record('ARENA', DateTime(2025, 3, 1)),
      ],
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.date, DateTime(2025, 2, 1));
  });
}
