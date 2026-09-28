import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/screens/home_screen.dart';

class _NoFavorites extends FavoriteArtistsNotifier {
  @override
  Future<List<FavoriteArtist>> build() async => const [];
}

void main() {
  testWidgets('HomeScreen renders title, add button and empty state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // テストではSupabaseに依存しないよう、records とお気に入りを空で固定
          recordsProvider.overrideWith((ref) => Stream.value(<Record>[])),
          favoriteArtistsProvider.overrideWith(_NoFavorites.new),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('RECOLLE'), findsWidgets);
    expect(find.byIcon(CupertinoIcons.plus_circle_fill), findsOneWidget);
    expect(find.text('ライブ'), findsOneWidget);
  });
}
