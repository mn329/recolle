import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:recolle/features/music/data/deezer_client.dart';

http.Response _json(Object body, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _placeholder =
    'https://cdn-images.dzcdn.net/images/artist//500x500-000000-80-0-0.jpg';

String _image(String hash) =>
    'https://cdn-images.dzcdn.net/images/artist/$hash/500x500-000000-80-0-0.jpg';

DeezerClient _clientReturning(List<Map<String, Object>> artists) {
  return DeezerClient(
    httpClient: MockClient((_) async => _json({'data': artists})),
  );
}

void main() {
  group('DeezerClient.findArtistImage', () {
    test('名前が一致するアーティストの画像を優先する', () async {
      final client = DeezerClient(
        httpClient: MockClient((req) async {
          expect(req.url.host, 'api.deezer.com');
          expect(req.url.queryParameters['q'], 'Aimer');
          return _json({
            'data': [
              {'name': 'Aimer & Someone', 'picture_big': _image('aaa')},
              {'name': 'aimer', 'picture_big': _image('bbb')},
            ],
          });
        }),
      );

      expect(await client.findArtistImage('Aimer'), _image('bbb'));
    });

    test('日本語名はローマ字表記で返っても最上位の結果を採用する', () async {
      final client = _clientReturning([
        {'name': 'Sakanaction', 'picture_big': _image('ccc')},
        {'name': 'Other', 'picture_big': _image('ddd')},
      ]);

      expect(await client.findArtistImage('サカナクション'), _image('ccc'));
    });

    test('英字名で一致がなければ別人の画像は使わない', () async {
      final client = _clientReturning([
        {'name': 'YOASOBI Tribute', 'picture_big': _image('eee')},
      ]);

      expect(await client.findArtistImage('YOASOBI'), isNull);
    });

    test('一致したアーティストに画像がなければ他の候補に進まない', () async {
      final client = _clientReturning([
        {'name': 'Tanaka!', 'picture_big': _placeholder},
        {'name': 'Tanaka', 'picture_big': _image('fff')},
      ]);

      expect(await client.findArtistImage('Tanaka!'), isNull);
    });

    test('レート制限（HTTP 200 の error）はユーザー向けの例外にする', () async {
      final client = DeezerClient(
        httpClient: MockClient(
          (_) async => _json({
            'error': {'type': 'Exception', 'message': 'Quota limit exceeded'},
          }),
        ),
      );

      expect(
        () => client.findArtistImage('Aimer'),
        throwsA(isA<UserFacingException>()),
      );
    });

    test('空の名前ではリクエストしない', () async {
      final client = DeezerClient(
        httpClient: MockClient((_) async => fail('should not be called')),
      );

      expect(await client.findArtistImage('  '), isNull);
    });
  });
}
