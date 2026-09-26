import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:recolle/features/music/data/concert_discovery_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:recolle/features/music/widgets/upcoming_concerts_section.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeClient extends ConcertDiscoveryClient {
  _FakeClient(this._respond) : super(FunctionsClient('http://localhost', {}));

  final Future<ConcertDiscoveryResult> Function() _respond;
  int calls = 0;

  @override
  Future<ConcertDiscoveryResult> discover(String artistName) {
    calls++;
    return _respond();
  }
}

void main() {
  group('ConcertDiscoveryResult.fromJson', () {
    test('形式の壊れた公演と https 以外のリンクは捨てる', () {
      final result = ConcertDiscoveryResult.fromJson({
        'events': [
          {
            'title': 'ARENA TOUR',
            'date': '2026-11-03',
            'openTime': '17:00',
            'startTime': '18:00',
            'venue': '東京ドーム',
            'city': '東京',
            'sourceUrl': 'https://example.com/live',
          },
          {'title': '日付なし', 'venue': '会場'},
          {'title': 'http のリンク', 'date': '2026-12-01', 'sourceUrl': 'http://x'},
          'not a map',
        ],
        'sources': [
          {'title': 'example.com', 'uri': 'https://example.com'},
          {'title': 'bad', 'uri': 'javascript:alert(1)'},
          {'title': 42, 'uri': 'https://example.com'},
        ],
        'searchEntryPoint': '<div>chips</div>',
        'fetchedAt': '2026-09-27T00:00:00Z',
      });

      expect(result.concerts.map((c) => c.title), ['ARENA TOUR', 'http のリンク']);
      final first = result.concerts.first;
      expect(first.date, DateTime(2026, 11, 3));
      expect(first.openTime, const ClockTime(17, 0));
      expect(first.startTime, const ClockTime(18, 0));
      expect(first.sourceUrl, Uri.parse('https://example.com/live'));
      expect(result.concerts[1].sourceUrl, isNull);
      expect(result.sources.map((s) => s.title), ['example.com']);
      expect(result.searchEntryPoint, '<div>chips</div>');
    });

    test('サーバーのエラーコードをユーザー向けの文に変える', () {
      expect(
        ConcertDiscoveryClient.messageForError('discovery_daily_limit', 429),
        contains('上限'),
      );
      expect(
        ConcertDiscoveryClient.messageForError('discovery_not_configured', 503),
        contains('API キー'),
      );
      expect(
        ConcertDiscoveryClient.messageForError(null, 500),
        contains('500'),
      );
    });
  });

  group('UpcomingConcertsSection', () {
    setUp(() {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
      view
        ..physicalSize = const Size(1170, 2532)
        ..devicePixelRatio = 3;
      addTearDown(view.reset);
    });

    Future<void> pump(
      WidgetTester tester,
      _FakeClient client, {
      List<Record> records = const [],
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            concertDiscoveryClientProvider.overrideWithValue(client),
            isOfflineReadOnlyProvider.overrideWithValue(false),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: UpcomingConcertsSection(
                  artistName: 'King Gnu',
                  records: records,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final result = ConcertDiscoveryResult(
      concerts: [
        DiscoveredConcert(
          title: 'ARENA TOUR 2026',
          date: DateTime(2026, 11, 3),
          openTime: const ClockTime(17, 0),
          startTime: const ClockTime(18, 0),
          venue: '東京ドーム',
          city: '東京',
          sourceUrl: Uri.parse('https://kinggnu.jp/live'),
        ),
        DiscoveredConcert(
          title: 'FES 2026',
          date: DateTime(2026, 12, 29),
          venue: '幕張メッセ',
        ),
      ],
      sources: [(title: 'kinggnu.jp', uri: Uri.parse('https://kinggnu.jp'))],
      fetchedAt: DateTime(2026, 9, 27, 9, 5),
    );

    testWidgets('押すまでは検索せず、押すと公演を並べて記録済みの日を示す', (tester) async {
      final client = _FakeClient(() async => result);
      await pump(
        tester,
        client,
        records: [
          Record(
            id: 'r1',
            type: RecordType.live,
            title: 'FES 2026',
            artistOrAuthor: 'King Gnu',
            date: DateTime(2026, 12, 29),
            ticketImageUrl: '',
          ),
        ],
      );

      expect(client.calls, 0);
      await tester.tap(find.text('公演を探す'));
      await tester.pumpAndSettle();

      expect(client.calls, 1);
      expect(find.text('ARENA TOUR 2026'), findsOneWidget);
      expect(find.text('東京ドーム・東京'), findsOneWidget);
      expect(find.text('開場 17:00 / 開演 18:00'), findsOneWidget);
      expect(find.text('kinggnu.jp'), findsWidgets);
      expect(find.text('記録済み'), findsOneWidget);
      expect(find.bySemanticsLabel('この公演を記録に追加'), findsOneWidget);
      expect(find.textContaining('9/27 09:05 時点'), findsOneWidget);
    });

    testWidgets('失敗したら理由を出し、もう一度探せる', (tester) async {
      var fail = true;
      final client = _FakeClient(() async {
        if (fail) throw const UserFacingException('今日の公演検索の上限に達しました。');
        return result;
      });
      await pump(tester, client);

      await tester.tap(find.text('公演を探す'));
      await tester.pumpAndSettle();
      expect(find.text('今日の公演検索の上限に達しました。'), findsOneWidget);
      // 自動では再試行しない
      expect(client.calls, 1);

      fail = false;
      await tester.tap(find.text('もう一度探す'));
      await tester.pumpAndSettle();
      expect(client.calls, 2);
      expect(find.text('ARENA TOUR 2026'), findsOneWidget);
    });
  });
}
