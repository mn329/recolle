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
      ticketImageUrl: '',
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
}
