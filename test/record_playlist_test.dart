import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:recolle/features/music/data/apple_music_playlist.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_playlist.dart';

http.Response _json(Object body, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// アーティストの曲一覧（attribute=artistTerm）と、1 曲ずつの検索（term）を返す。
ItunesClient _itunes({
  required Map<String, List<Map<String, Object>>> catalogs,
  Map<String, List<Map<String, Object>>> individual = const {},
  Set<String> failingTerms = const {},
  List<String>? requestedTerms,
}) => ItunesClient(
  httpClient: MockClient((req) async {
    final q = req.url.queryParameters;
    final term = q['term']!;
    requestedTerms?.add(term);
    if (q['attribute'] == 'artistTerm') {
      return _json({'results': catalogs[term] ?? const []});
    }
    if (failingTerms.contains(term)) return http.Response('', 500);
    return _json({'results': individual[term] ?? const []});
  }),
);

Record _live({
  String setlist = '',
  List<RecordAct> acts = const [],
  String? venue = 'Zepp Haneda',
}) => Record.fromJson({
  'id': 'r1',
  'user_id': 'u1',
  'type': 'live',
  'title': 'ZEPP TOUR',
  'artist_or_author': 'YOASOBI',
  'date': '2026-09-27',
  'ticket_image_url': '',
  'setlist': setlist,
  'venue': venue,
  'acts': [for (final a in acts) a.toJson()],
});

void main() {
  group('findSongIds', () {
    test('曲一覧から曲名が一致する曲を探し、付記の違いも許す', () async {
      final terms = <String>[];
      final client = _itunes(
        catalogs: {
          'YOASOBI': [
            {'trackId': 1, 'trackName': '夜に駆ける', 'artistName': 'YOASOBI'},
            {'trackId': 2, 'trackName': '群青 (Live)', 'artistName': 'YOASOBI'},
            {'trackId': 3, 'trackName': '群青', 'artistName': 'YOASOBI'},
            {
              'trackId': 4,
              'trackName': '祝福 - from CrosSing',
              'artistName': 'YOASOBI',
            },
            {'trackId': 9, 'trackName': 'アイドル', 'artistName': '別の人'},
          ],
        },
        requestedTerms: terms,
      );

      final ids = await client.findSongIds(
        artistName: 'YOASOBI',
        titles: ['夜に駆ける', '群青', '祝福'],
      );

      // 付記なしの完全一致（群青 = 3）を付記付き（2）より優先する
      expect(ids, {'夜に駆ける': 1, '群青': 3, '祝福': 4});
      expect(terms, ['YOASOBI']);
    });

    test('曲一覧にない曲は 1 曲ずつ検索し、曲名が違う結果は使わない', () async {
      final client = _itunes(
        catalogs: const {},
        individual: {
          'YOASOBI アイドル': [
            {'trackId': 5, 'trackName': 'アイドル', 'artistName': 'YOASOBI'},
          ],
          'YOASOBI 新曲': [
            {'trackId': 6, 'trackName': '別の曲', 'artistName': 'YOASOBI'},
          ],
        },
      );

      final ids = await client.findSongIds(
        artistName: 'YOASOBI',
        titles: ['アイドル', '新曲'],
      );

      expect(ids, {'アイドル': 5});
    });

    test('一部の曲の検索に失敗しても、見つかった曲は返す', () async {
      final client = _itunes(
        catalogs: const {},
        individual: {
          'YOASOBI アイドル': [
            {'trackId': 5, 'trackName': 'アイドル', 'artistName': 'YOASOBI'},
          ],
        },
        failingTerms: {'YOASOBI 群青'},
      );

      final ids = await client.findSongIds(
        artistName: 'YOASOBI',
        titles: ['アイドル', '群青'],
      );

      expect(ids, {'アイドル': 5});
    });
  });

  group('planRecordPlaylist', () {
    test('区切り・MC を除き、セトリの順に並べて、見つからない曲を分ける', () async {
      final client = _itunes(
        catalogs: {
          'YOASOBI': [
            {'trackId': 1, 'trackName': '夜に駆ける', 'artistName': 'YOASOBI'},
            {'trackId': 5, 'trackName': 'アイドル', 'artistName': 'YOASOBI'},
          ],
        },
      );
      final record = _live(setlist: 'アイドル\nMC\n未発表曲\n--- アンコール ---\n夜に駆ける');

      final plan = await planRecordPlaylist(client, record);

      expect(plan.songIds, [5, 1]);
      expect(plan.missingTitles, ['未発表曲']);
    });

    test('対バンは出演者の順に、それぞれのアーティストの曲から探す', () async {
      final client = _itunes(
        catalogs: {
          'sumika': [
            {'trackId': 10, 'trackName': 'Lovers', 'artistName': 'sumika'},
          ],
          'YOASOBI': [
            {'trackId': 1, 'trackName': '夜に駆ける', 'artistName': 'YOASOBI'},
          ],
        },
      );
      final record = _live(
        acts: const [
          RecordAct(artist: 'sumika', songs: ['Lovers']),
          RecordAct(artist: 'YOASOBI', songs: ['夜に駆ける'], isMain: true),
        ],
      );

      final plan = await planRecordPlaylist(client, record);

      expect(plan.songIds, [10, 1]);
      expect(plan.missingTitles, isEmpty);
    });
  });

  test('プレイリストの名前は公演名と日付、説明は出演者と会場', () {
    final record = _live();
    expect(recordPlaylistName(record), 'ZEPP TOUR 2026.09.27');
    expect(
      recordPlaylistDescription(record),
      'YOASOBI @ Zepp Haneda （recolle で作成）',
    );
    expect(
      recordPlaylistDescription(_live(venue: null)),
      'YOASOBI （recolle で作成）',
    );
  });

  group('AppleMusicPlaylistService', () {
    const channel = MethodChannel('test/apple_music');

    setUp(TestWidgetsFlutterBinding.ensureInitialized);

    void mockChannel(Future<Object?> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
    }

    test('曲 ID を文字列で渡し、作成結果を読み取る', () async {
      MethodCall? received;
      mockChannel((call) async {
        received = call;
        return {'url': 'https://music.apple.com/library/p.1'};
      });

      final result = await AppleMusicPlaylistService(
        channel: channel,
      ).createPlaylist(name: 'ZEPP TOUR', songIds: [5, 1], description: 'd');

      expect(received!.method, 'createPlaylist');
      expect(received!.arguments, {
        'name': 'ZEPP TOUR',
        'songIds': ['5', '1'],
        'description': 'd',
      });
      expect(result.url, Uri.parse('https://music.apple.com/library/p.1'));
    });

    test('iOS 側のエラーを分かるメッセージにする', () async {
      mockChannel(
        (_) async => throw PlatformException(code: 'no_subscription'),
      );

      await expectLater(
        AppleMusicPlaylistService(
          channel: channel,
        ).createPlaylist(name: 'x', songIds: [1]),
        throwsA(
          isA<UserFacingException>().having(
            (e) => e.userMessage,
            'userMessage',
            'プレイリストの作成には Apple Music への加入が必要です。',
          ),
        ),
      );
    });

    test('エラーコードごとのメッセージ', () {
      expect(
        AppleMusicPlaylistService.messageForError('unsupported_os'),
        contains('iOS 16'),
      );
      expect(
        AppleMusicPlaylistService.messageForError('denied'),
        contains('設定アプリ'),
      );
      expect(
        AppleMusicPlaylistService.messageForError('something'),
        'プレイリストを作成できませんでした。',
      );
    });
  });
}
