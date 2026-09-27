import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recolle/features/music/data/artist_artwork_finder.dart';
import 'package:recolle/features/music/data/deezer_client.dart';
import 'package:recolle/features/music/data/itunes_client.dart';

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _deezerImage =
    'https://cdn-images.dzcdn.net/images/artist/ggg/500x500-000000-80-0-0.jpg';
const _albumArtwork = 'https://is1-ssl.mzstatic.com/image/a/400x400bb.jpg';

DeezerClient _deezerReturning(List<Map<String, Object>> artists) =>
    DeezerClient(httpClient: MockClient((_) async => _json({'data': artists})));

DeezerClient _failingDeezer() =>
    DeezerClient(httpClient: MockClient((_) async => http.Response('', 500)));

ItunesClient _itunesWithAlbum() => ItunesClient(
  httpClient: MockClient(
    (_) async => _json({
      'results': [
        {
          'artistName': 'Aimer',
          'artworkUrl100': 'https://is1-ssl.mzstatic.com/image/a/100x100bb.jpg',
        },
      ],
    }),
  ),
);

void main() {
  group('ArtistArtworkFinder.find', () {
    test('Deezer の画像があればアルバムジャケットより優先する', () async {
      final finder = ArtistArtworkFinder(
        deezer: _deezerReturning([
          {'name': 'Aimer', 'picture_big': _deezerImage},
        ]),
        itunes: ItunesClient(
          httpClient: MockClient((_) async => fail('should not be called')),
        ),
      );

      expect(await finder.find('Aimer'), _deezerImage);
    });

    test('Deezer が失敗したら iTunes のアルバムジャケットで代用する', () async {
      final finder = ArtistArtworkFinder(
        deezer: _failingDeezer(),
        itunes: _itunesWithAlbum(),
      );

      expect(await finder.find('Aimer'), _albumArtwork);
    });

    test('Deezer も iTunes も失敗したら、例外にせず null を返す', () async {
      final finder = ArtistArtworkFinder(
        deezer: _failingDeezer(),
        itunes: ItunesClient(
          httpClient: MockClient((_) async => http.Response('', 503)),
        ),
      );

      expect(await finder.find('Aimer'), isNull);
    });
  });

  group('ArtistArtworkFinder.findArtistImage', () {
    test('アルバムジャケットでは代用しない', () async {
      final finder = ArtistArtworkFinder(
        deezer: _deezerReturning(const []),
        itunes: ItunesClient(
          httpClient: MockClient((_) async => fail('should not be called')),
        ),
      );

      expect(await finder.findArtistImage('Aimer'), isNull);
    });
  });

  group('ArtistArtworkFinder.isAlbumArtworkFallback', () {
    test('iTunes のジャケットだけを代用画像とみなす', () {
      expect(ArtistArtworkFinder.isAlbumArtworkFallback(_albumArtwork), isTrue);
      expect(ArtistArtworkFinder.isAlbumArtworkFallback(_deezerImage), isFalse);
      expect(ArtistArtworkFinder.isAlbumArtworkFallback('not a url'), isFalse);
    });
  });
}
