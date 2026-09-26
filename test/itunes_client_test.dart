import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:recolle/features/music/data/itunes_client.dart';

http.Response _json(Object body, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('searchSongs は別アーティストの曲と重複曲名を除外する', () async {
    final client = ItunesClient(
      httpClient: MockClient((req) async {
        expect(req.url.queryParameters['entity'], 'song');
        expect(req.url.queryParameters['term'], 'YOASOBI 夜に');
        return _json({
          'results': [
            {
              'trackId': 1,
              'trackName': '夜に駆ける',
              'artistName': 'YOASOBI',
              'artworkUrl100': 'https://example.com/a/100x100bb.jpg',
            },
            {'trackId': 2, 'trackName': '夜に駆ける', 'artistName': 'YOASOBI'},
            {
              'trackId': 3,
              'trackName': '夜に駆ける (Cover)',
              'artistName': 'Someone',
            },
          ],
        });
      }),
    );

    final songs = await client.searchSongs(artistName: 'YOASOBI', term: '夜に');

    expect(songs.map((s) => s.title), ['夜に駆ける']);
    expect(songs.single.artworkUrl, 'https://example.com/a/400x400bb.jpg');
  });

  test('同じ検索は2回目にキャッシュを使う', () async {
    var calls = 0;
    final client = ItunesClient(
      httpClient: MockClient((req) async {
        calls++;
        return _json({
          'results': [
            {
              'artistId': 10,
              'artistName': 'Aimer',
              'primaryGenreName': 'J-Pop',
            },
          ],
        });
      }),
    );

    await client.searchArtists('Aimer');
    final second = await client.searchArtists('Aimer');

    expect(calls, 1);
    expect(second.single.name, 'Aimer');
  });

  test('レート制限時はユーザー向けの例外を投げる', () async {
    final client = ItunesClient(
      httpClient: MockClient((_) async => http.Response('', 403)),
    );

    expect(
      () => client.searchArtists('Aimer'),
      throwsA(isA<UserFacingException>()),
    );
  });

  group('localizeSongTitles', () {
    ItunesClient clientWith({
      required List<Map<String, Object>> jp,
      required List<Map<String, Object>> us,
      Map<String, List<Map<String, Object>>> individual = const {},
    }) {
      return ItunesClient(
        httpClient: MockClient((req) async {
          final q = req.url.queryParameters;
          if (q['attribute'] == 'artistTerm') {
            return _json({'results': q['country'] == 'US' ? us : jp});
          }
          return _json({'results': individual[q['term']] ?? const []});
        }),
      );
    }

    test('米国ストアのローマ字名と日本ストアを trackId で突き合わせる', () async {
      final client = clientWith(
        jp: [
          {'trackId': 1, 'trackName': '劇上', 'artistName': 'YOASOBI'},
          {'trackId': 2, 'trackName': 'アイドル', 'artistName': 'YOASOBI'},
          {'trackId': 3, 'trackName': 'Idol', 'artistName': 'YOASOBI'},
        ],
        us: [
          {'trackId': 3, 'trackName': 'Idol', 'artistName': 'YOASOBI'},
          {'trackId': 2, 'trackName': 'Idol', 'artistName': 'YOASOBI'},
          {'trackId': 1, 'trackName': 'Gekijyo', 'artistName': 'YOASOBI'},
        ],
      );

      final result = await client.localizeSongTitles(
        artistName: 'YOASOBI',
        titles: ['Gekijyo', 'Idol', '夜に駆ける'],
      );

      expect(result, {'Gekijyo': '劇上', 'Idol': 'アイドル'});
    });

    test('突き合わせで見つからない曲は個別検索し、付記を落とす', () async {
      final client = clientWith(
        jp: const [],
        us: const [],
        individual: {
          'YOASOBI Shukufuku': [
            {
              'trackId': 9,
              'trackName': '祝福 - from CrosSing',
              'artistName': 'YOASOBI',
            },
          ],
          'YOASOBI Unknown': [
            {'trackId': 8, 'trackName': '別の曲', 'artistName': 'Someone'},
          ],
        },
      );

      final result = await client.localizeSongTitles(
        artistName: 'YOASOBI',
        titles: ['Shukufuku', 'Unknown'],
      );

      expect(result, {'Shukufuku': '祝福'});
    });
  });

  test('topSongs は先頭のアーティスト行を除き、別バージョンの同名曲をまとめる', () async {
    final client = ItunesClient(
      httpClient: MockClient((req) async {
        expect(req.url.path, '/lookup');
        return _json({
          'results': [
            {'wrapperType': 'artist', 'artistId': 1, 'artistName': 'YOASOBI'},
            {
              'trackId': 10,
              'trackName': 'アイドル',
              'artistName': 'YOASOBI',
              'artistId': 1,
              'collectionName': 'アイドル - Single',
              'trackTimeMillis': 213000,
              'releaseDate': '2023-04-12T12:00:00Z',
              'trackViewUrl': 'https://music.apple.com/jp/song/10',
              'previewUrl': 'https://audio-ssl.itunes.apple.com/preview.m4a',
            },
            {
              'trackId': 11,
              'trackName': 'アイドル (Piano Ver.)',
              'artistName': 'YOASOBI',
            },
            {'trackId': 12, 'trackName': '夜に駆ける', 'artistName': 'YOASOBI'},
          ],
        });
      }),
    );

    final songs = await client.topSongs(1);

    expect(songs.map((s) => s.title), ['アイドル', '夜に駆ける']);
    final idol = songs.first;
    expect(idol.duration, const Duration(minutes: 3, seconds: 33));
    expect(idol.releaseDate?.year, 2023);
    expect(idol.appleMusicUrl.toString(), 'https://music.apple.com/jp/song/10');
    expect(
      idol.previewUrl.toString(),
      'https://audio-ssl.itunes.apple.com/preview.m4a',
    );
    expect(songs.last.previewUrl, isNull);
  });

  test('findArtist は完全一致を優先する', () async {
    final client = ItunesClient(
      httpClient: MockClient((req) async {
        return _json({
          'results': [
            {'artistId': 1, 'artistName': 'YOASOBI × Someone'},
            {
              'artistId': 2,
              'artistName': 'YOASOBI',
              'artistLinkUrl': 'https://music.apple.com/jp/artist/2',
            },
          ],
        });
      }),
    );

    final artist = await client.findArtist('yoasobi');

    expect(artist?.id, 2);
    expect(
      artist?.appleMusicUrl.toString(),
      'https://music.apple.com/jp/artist/2',
    );
  });

  test('空の検索語ではリクエストしない', () async {
    final client = ItunesClient(
      httpClient: MockClient((_) async => fail('should not be called')),
    );

    expect(await client.searchArtists('  '), isEmpty);
    expect(await client.searchSongs(artistName: 'A', term: ''), isEmpty);
  });
}
