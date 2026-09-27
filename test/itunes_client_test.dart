import 'dart:async';
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

  group('searchArtists の日本語名', () {
    ItunesClient clientWith({
      required List<Map<String, Object>> artists,
      List<Map<String, Object>> songs = const [],
      bool songSearchFails = false,
    }) {
      return ItunesClient(
        httpClient: MockClient((req) async {
          if (req.url.queryParameters['entity'] == 'musicArtist') {
            return _json({'results': artists});
          }
          if (songSearchFails) return http.Response('', 500);
          return _json({'results': songs});
        }),
      );
    }

    test('日本語で探すと、曲の検索結果にある日本語名で返す', () async {
      final client = clientWith(
        artists: [
          {'artistId': 1, 'artistName': 'sakanaction'},
          {'artistId': 2, 'artistName': 'Ami Kusakari'},
        ],
        songs: [
          {'artistId': 1, 'artistName': 'サカナクション'},
          {'artistId': 1, 'artistName': 'サカナクション & 誰か'},
          {'artistId': 1, 'artistName': 'サカナクション'},
          {'artistId': 3, 'artistName': '別の人'},
        ],
      );

      final artists = await client.searchArtists('サカナクション');

      expect(artists.map((a) => a.name), ['サカナクション', 'Ami Kusakari']);
      expect(artists.first.id, 1);
    });

    test('英字で探したときは曲の検索をしない', () async {
      final entities = <String?>[];
      final client = ItunesClient(
        httpClient: MockClient((req) async {
          entities.add(req.url.queryParameters['entity']);
          return _json({
            'results': [
              {'artistId': 1, 'artistName': 'sakanaction'},
            ],
          });
        }),
      );

      final artists = await client.searchArtists('sakanaction');

      expect(artists.single.name, 'sakanaction');
      expect(entities, ['musicArtist']);
    });

    test('日本語名の検索に失敗しても、英字名のまま返す', () async {
      final client = clientWith(
        artists: [
          {'artistId': 1, 'artistName': 'sakanaction'},
        ],
        songSearchFails: true,
      );

      final artists = await client.searchArtists('サカナクション');

      expect(artists.single.name, 'sakanaction');
    });
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

    test('カタログも個別検索も、前のリクエストを待たずに同時に投げる', () async {
      final started = <String>[];
      final release = Completer<void>();
      final client = ItunesClient(
        httpClient: MockClient((req) async {
          final q = req.url.queryParameters;
          started.add(
            q['attribute'] == 'artistTerm' ? q['country']! : q['term']!,
          );
          await release.future;
          return _json({'results': const []});
        }),
      );

      final result = client.localizeSongTitles(
        artistName: 'YOASOBI',
        titles: ['Shukufuku', 'Gekijyo'],
      );
      await pumpEventQueue();
      expect(started, unorderedEquals(['JP', 'US']));

      release.complete();
      await result;
      expect(
        started.skip(2),
        unorderedEquals(['YOASOBI Shukufuku', 'YOASOBI Gekijyo']),
      );
    });

    test('個別検索の一部がレート制限で失敗しても、見つかった曲は日本語にする', () async {
      final client = ItunesClient(
        httpClient: MockClient((req) async {
          final q = req.url.queryParameters;
          if (q['attribute'] == 'artistTerm') {
            return _json({'results': const []});
          }
          if (q['term'] == 'YOASOBI Gekijyo') return http.Response('', 403);
          return _json({
            'results': [
              {'trackId': 9, 'trackName': '祝福', 'artistName': 'YOASOBI'},
            ],
          });
        }),
      );

      final result = await client.localizeSongTitles(
        artistName: 'YOASOBI',
        titles: ['Gekijyo', 'Shukufuku'],
      );

      expect(result, {'Shukufuku': '祝福'});
    });

    test('先読み中のカタログには相乗りし、同じリクエストを二重に投げない', () async {
      var catalogRequests = 0;
      final release = Completer<void>();
      final client = ItunesClient(
        httpClient: MockClient((req) async {
          if (req.url.queryParameters['attribute'] == 'artistTerm') {
            catalogRequests++;
            await release.future;
          }
          return _json({'results': const []});
        }),
      );

      final prefetch = client.prefetchSongCatalog('YOASOBI');
      final result = client.localizeSongTitles(
        artistName: 'YOASOBI',
        titles: ['Gekijyo'],
      );
      release.complete();
      await Future.wait([prefetch, result]);

      expect(catalogRequests, 2);
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
