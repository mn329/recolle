import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:recolle/features/records/data/work_search_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

http.Response _json(Object body, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

WorkSearchClient _client(
  Future<http.Response> Function(http.Request) handler,
) => WorkSearchClient(
  FunctionsClient(
    'https://example.supabase.co/functions/v1',
    {},
    httpClient: MockClient(handler),
  ),
);

void main() {
  test('種別と入力を送り、候補を読み取る（壊れた候補は捨てる）', () async {
    final client = _client((req) async {
      expect(req.url.path, endsWith('/work-search'));
      expect(jsonDecode(req.body), {'type': 'movie', 'query': '君の名は'});
      return _json({
        'works': [
          {
            'title': '君の名は。',
            'creator': '新海誠',
            'year': 2016,
            'artworkUrl': 'https://image.tmdb.org/t/p/w185/a.jpg',
            'description': null,
          },
          {
            'title': 'Your Name',
            'year': 'x',
            'artworkUrl': 'http://insecure.example.com/b.jpg',
            'description': '  ',
          },
          {'creator': '題名なし'},
          'broken',
        ],
      });
    });

    final movies = await client.searchMovies(' 君の名は ');

    expect(movies.map((m) => m.title), ['君の名は。', 'Your Name']);
    expect(movies.first.creator, '新海誠');
    expect(movies.first.year, 2016);
    expect(movies.first.artworkUrl, 'https://image.tmdb.org/t/p/w185/a.jpg');
    expect(movies.last.year, isNull);
    expect(movies.last.artworkUrl, isNull);
    expect(movies.last.description, isNull);
  });

  test('同じ検索はキャッシュを使い、同時に走っても問い合わせは 1 回にまとめる', () async {
    var calls = 0;
    final client = _client((req) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return _json({
        'works': [
          {'title': 'ノルウェイの森', 'creator': '村上春樹'},
        ],
      });
    });

    final results = await Future.wait([
      client.searchBooks('ノルウェイの森'),
      client.searchBooks('ノルウェイの森'),
    ]);
    await client.searchBooks('ノルウェイの森');

    expect(calls, 1);
    expect(results.map((r) => r.single.title), ['ノルウェイの森', 'ノルウェイの森']);
  });

  test('映画と本は別々にキャッシュする', () async {
    final types = <Object?>[];
    final client = _client((req) async {
      types.add((jsonDecode(req.body) as Map)['type']);
      return _json({'works': <Object>[]});
    });

    await client.searchMovies('国宝');
    await client.searchBooks('国宝');

    expect(types, ['movie', 'book']);
  });

  test('失敗した検索はキャッシュせず、次は問い合わせ直す', () async {
    var calls = 0;
    final client = _client((_) async {
      calls++;
      return calls == 1
          ? _json({'error': 'work_search_upstream_error'}, status: 502)
          : _json({
              'works': [
                {'title': '国宝'},
              ],
            });
    });

    await expectLater(
      client.searchMovies('国宝'),
      throwsA(isA<UserFacingException>()),
    );
    final movies = await client.searchMovies('国宝');

    expect(calls, 2);
    expect(movies.single.title, '国宝');
  });

  test('サーバーのエラーを分かるメッセージで伝える', () async {
    final client = _client(
      (_) async => _json({'error': 'work_search_rate_limited'}, status: 429),
    );

    await expectLater(
      client.searchBooks('国宝'),
      throwsA(
        isA<UserFacingException>().having(
          (e) => e.userMessage,
          'userMessage',
          '本の検索が混み合っています。少し待ってからお試しください。',
        ),
      ),
    );
  });

  test('サーバーに接続できないときも、分かるメッセージで伝える', () async {
    final client = _client(
      (_) async => throw http.ClientException('Failed host lookup'),
    );

    await expectLater(
      client.searchMovies('国宝'),
      throwsA(
        isA<UserFacingException>().having(
          (e) => e.userMessage,
          'userMessage',
          contains('サーバーに接続できませんでした'),
        ),
      ),
    );
  });

  test('エラーコードごとのメッセージ', () {
    expect(
      WorkSearchClient.messageForError(
        'work_search_not_configured',
        503,
        type: 'movie',
      ),
      '映画の検索は現在ご利用いただけません。',
    );
    expect(
      WorkSearchClient.messageForError(
        'work_search_timeout',
        504,
        type: 'book',
      ),
      '本の情報の取得に時間がかかっています。少し待ってからお試しください。',
    );
    expect(
      WorkSearchClient.messageForError(null, 500, type: 'movie'),
      '映画の情報を取得できませんでした (500)。',
    );
  });

  test('空の入力では問い合わせない', () async {
    final client = _client((_) async => fail('should not request'));

    expect(await client.searchBooks('  '), isEmpty);
    expect(await client.searchMovies(''), isEmpty);
  });
}
