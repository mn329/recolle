import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:recolle/features/records/data/work_search_client.dart';

http.Response _json(Object body, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object> _claims({
  List<String> directors = const [],
  String? date,
}) => {
  'claims': {
    'P57': [
      for (final id in directors)
        {
          'mainsnak': {
            'datavalue': {
              'value': {'id': id},
            },
          },
        },
    ],
    if (date != null)
      'P577': [
        {
          'mainsnak': {
            'datavalue': {
              'value': {'time': date},
            },
          },
        },
        {
          'mainsnak': {
            'datavalue': {
              'value': {'time': '+2017-01-01T00:00:00Z'},
            },
          },
        },
      ],
  },
};

void main() {
  group('searchMovies', () {
    test('映画だけを残し、監督と最も早い公開年を添える', () async {
      final client = WorkSearchClient(
        httpClient: MockClient((req) async {
          final q = req.url.queryParameters;
          expect(req.headers['User-Agent'], contains('recolle'));
          switch (q['action']) {
            case 'wbsearchentities':
              expect(q['search'], '君の名は');
              return _json({
                'search': [
                  {
                    'id': 'Q1',
                    'label': '君の名は。',
                    'description': '日本のアニメーション映画 (2016)',
                  },
                  {
                    'id': 'Q2',
                    'label': '君の名は。',
                    'description': 'RADWIMPSのサウンドトラック',
                  },
                  {'id': 'Q3', 'label': '君の名は', 'description': '日本のラジオドラマ'},
                  {
                    'id': 'Q4',
                    'label': '君の名は 第二部 (1953年の映画)',
                    'description': '1953 film by Hideo Ōba',
                  },
                ],
              });
            case 'wbgetentities' when q['props'] == 'claims':
              expect(q['ids'], 'Q1|Q4');
              return _json({
                'entities': {
                  'Q1': _claims(
                    directors: ['P100'],
                    date: '+2016-08-26T00:00:00Z',
                  ),
                  'Q4': _claims(),
                },
              });
            case 'wbgetentities':
              expect(q['ids'], 'P100');
              return _json({
                'entities': {
                  'P100': {
                    'labels': {
                      'ja': {'value': '新海誠'},
                    },
                  },
                },
              });
          }
          fail('unexpected request: ${req.url}');
        }),
      );

      final movies = await client.searchMovies('君の名は');

      expect(movies.map((m) => m.title), ['君の名は。', '君の名は 第二部']);
      expect(movies.first.creator, '新海誠');
      expect(movies.first.year, 2016);
      expect(movies.last.creator, isNull);
    });

    test('監督が取れなくても、題名の候補は出す', () async {
      final client = WorkSearchClient(
        httpClient: MockClient((req) async {
          if (req.url.queryParameters['action'] == 'wbsearchentities') {
            return _json({
              'search': [
                {'id': 'Q1', 'label': 'ラストマイル', 'description': '2024年の日本の映画'},
              ],
            });
          }
          return http.Response('down', 503);
        }),
      );

      final movies = await client.searchMovies('ラストマイル');

      expect(movies.single.title, 'ラストマイル');
      expect(movies.single.creator, isNull);
    });

    test('検索そのものが失敗したら、分かるメッセージで伝える', () async {
      final client = WorkSearchClient(
        httpClient: MockClient((_) async => http.Response('busy', 429)),
      );

      await expectLater(
        client.searchMovies('国宝'),
        throwsA(
          isA<UserFacingException>().having(
            (e) => e.userMessage,
            'userMessage',
            contains('混み合っています'),
          ),
        ),
      );
    });
  });

  group('searchBooks', () {
    test('電子書籍の書名・著者・年・表紙を返し、同じ検索はキャッシュを使う', () async {
      var calls = 0;
      final client = WorkSearchClient(
        httpClient: MockClient((req) async {
          calls++;
          expect(req.url.queryParameters['media'], 'ebook');
          expect(req.url.queryParameters['country'], 'JP');
          return _json({
            'results': [
              {
                'trackName': 'ノルウェイの森',
                'artistName': '村上春樹',
                'releaseDate': '2018-11-26T13:02:55Z',
                'artworkUrl100': 'https://example.com/a/100x100bb.jpg',
              },
              {'artistName': '題名なし'},
            ],
          });
        }),
      );

      final books = await client.searchBooks('ノルウェイの森');
      await client.searchBooks('ノルウェイの森');

      expect(calls, 1);
      expect(books.single.title, 'ノルウェイの森');
      expect(books.single.creator, '村上春樹');
      expect(books.single.year, 2018);
      expect(books.single.artworkUrl, 'https://example.com/a/200x200bb.jpg');
    });

    test('空の入力では問い合わせない', () async {
      final client = WorkSearchClient(
        httpClient: MockClient((_) async => fail('should not request')),
      );

      expect(await client.searchBooks('  '), isEmpty);
      expect(await client.searchMovies(''), isEmpty);
    });
  });
}
