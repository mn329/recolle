import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/favorite_artist_chips.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/screens/home_screen.dart';

class _Favorites extends FavoriteArtistsNotifier {
  @override
  Future<List<FavoriteArtist>> build() async => [
    FavoriteArtist(id: '1', name: 'Aimer', createdAt: DateTime(2026)),
  ];
}

Record _record(String id, RecordType type, String title, String creator) =>
    Record(
      id: id,
      type: type,
      title: title,
      artistOrAuthor: creator,
      date: DateTime(2026, 1, 10),
    );

void main() {
  testWidgets('ライブ以外の種別では、お気に入りアーティストのチップと絞り込みを外す', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteArtistsProvider.overrideWith(_Favorites.new),
          isOfflineReadOnlyProvider.overrideWithValue(false),
          recordsProvider.overrideWith(
            (ref) => Stream.value([
              _record('1', RecordType.live, 'ツアー', 'Aimer'),
              _record('2', RecordType.movie, 'ラストマイル', '塚原あゆ子'),
            ]),
          ),
        ],
        child: MaterialApp(theme: AppTheme.darkTheme, home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FavoriteArtistChips), findsOneWidget);
    await tester.tap(find.text('Aimer').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('映画'));
    await tester.pumpAndSettle();

    expect(find.byType(FavoriteArtistChips), findsNothing);
    // ライブで選んだアーティストで映画を絞り込まない
    expect(find.text('ラストマイル'), findsWidgets);
  });

  testWidgets('「これまで」を古い順やライブ形態ごとに並べ替えられる', (tester) async {
    Record live(String title, DateTime date, EventFormat format) => Record(
      id: title,
      type: RecordType.live,
      title: title,
      artistOrAuthor: 'Aimer',
      date: date,
      eventFormat: format,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteArtistsProvider.overrideWith(_Favorites.new),
          isOfflineReadOnlyProvider.overrideWithValue(false),
          recordsProvider.overrideWith(
            (ref) => Stream.value([
              live('新しいワンマン', DateTime(2026, 1, 10), EventFormat.oneman),
              live('古いフェス', DateTime(2025, 5, 1), EventFormat.festival),
            ]),
          ),
        ],
        child: MaterialApp(theme: AppTheme.darkTheme, home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    double top(String title) => tester.getTopLeft(find.text(title).first).dy;
    expect(top('新しいワンマン'), lessThan(top('古いフェス')));

    await tester.tap(find.text('新しい順'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('古い順'));
    await tester.pumpAndSettle();
    expect(top('古いフェス'), lessThan(top('新しいワンマン')));

    await tester.tap(find.text('古い順'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ライブ形態順'));
    await tester.pumpAndSettle();
    expect(find.text('ワンマン・1件'), findsOneWidget);
    expect(find.text('フェス・1件'), findsOneWidget);
    expect(top('新しいワンマン'), lessThan(top('古いフェス')));
  });

  testWidgets('読み込みに失敗しても表示中の一覧は残し、再読み込みを案内する', (tester) async {
    Stream<List<Record>> dataThenError() async* {
      yield [_record('1', RecordType.live, 'ツアー', 'Aimer')];
      throw Exception('realtime disconnected');
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteArtistsProvider.overrideWith(_Favorites.new),
          isOfflineReadOnlyProvider.overrideWithValue(false),
          recordsProvider.overrideWith((ref) => dataThenError()),
        ],
        child: MaterialApp(theme: AppTheme.darkTheme, home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ツアー'), findsWidgets);
    expect(find.textContaining('最新の記録を読み込めませんでした'), findsOneWidget);
    expect(find.text('再読み込み'), findsOneWidget);
  });
}
