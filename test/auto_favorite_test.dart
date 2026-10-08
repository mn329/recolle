import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/favorites/auto_favorite.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/records/models/record.dart';

Record _record({
  String artist = 'YOASOBI',
  RecordType type = RecordType.live,
  EventFormat format = EventFormat.oneman,
  List<RecordAct> acts = const [],
}) => Record(
  id: 'r',
  type: type,
  title: 'T',
  artistOrAuthor: artist,
  date: DateTime(2026, 9, 1),
  eventFormat: format,
  acts: acts,
);

FavoriteArtist _favorite(String name) =>
    FavoriteArtist(id: name, name: name, createdAt: DateTime(2026));

void main() {
  group('artistsToAutoFavorite', () {
    test('ワンマンのアーティストを入れる', () {
      expect(artistsToAutoFavorite(_record(), favorites: const []), [
        'YOASOBI',
      ]);
    });

    test('表記ゆれを含め、お気に入り済みのアーティストは入れない', () {
      expect(
        artistsToAutoFavorite(
          _record(artist: 'yoasobi '),
          favorites: [_favorite('YOASOBI')],
        ),
        isEmpty,
      );
    });

    test('対バン・フェスはお目当ての出演者だけを入れる', () {
      final fes = _record(
        artist: 'Vaundy',
        format: EventFormat.festival,
        acts: const [
          RecordAct(artist: 'Vaundy', isMain: true),
          RecordAct(artist: 'sumika'),
          RecordAct(artist: 'back number'),
        ],
      );
      expect(artistsToAutoFavorite(fes, favorites: const []), ['Vaundy']);

      final noMain = _record(
        format: EventFormat.taiban,
        acts: const [
          RecordAct(artist: 'sumika'),
          RecordAct(artist: 'Vaundy'),
        ],
      );
      expect(artistsToAutoFavorite(noMain, favorites: const []), isEmpty);
    });

    test('ライブ以外の記録（監督・著者）は入れない', () {
      expect(
        artistsToAutoFavorite(
          _record(artist: '押山清高', type: RecordType.movie),
          favorites: const [],
        ),
        isEmpty,
      );
    });

    test('編集では、元の記録から新しく加わったアーティストだけを入れる', () {
      // 自分でお気に入りから外した YOASOBI は、保存し直しても戻さない
      expect(
        artistsToAutoFavorite(
          _record(),
          previous: _record(),
          favorites: const [],
        ),
        isEmpty,
      );
      expect(
        artistsToAutoFavorite(
          _record(artist: 'Vaundy'),
          previous: _record(),
          favorites: const [],
        ),
        ['Vaundy'],
      );
    });
  });

  group('addAutoFavorites', () {
    test('1 組の追加に失敗しても、残りは追加する', () async {
      final saved = <String>[];
      final added = await addAutoFavorites(
        ['A', 'B', 'C'],
        add: (name) async {
          if (name == 'B') throw Exception('duplicate');
          saved.add(name);
        },
      );

      expect(added, ['A', 'C']);
      expect(saved, ['A', 'C']);
    });
  });
}
