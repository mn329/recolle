import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/pick_artist_image.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/screens/favorites_screen.dart';
import 'package:recolle/features/records/providers/records_provider.dart';

import 'support/favorite_artists_fakes.dart';

const _storedCustomImage = 'https://img/custom-old';

/// お気に入り画面を開く。[pickedFile] は、画像の選択・切り抜きで返されるファイル（null ならキャンセル）。
Future<void> _pumpScreen(
  WidgetTester tester, {
  required FakeFavoriteArtistsRepository repository,
  File? pickedFile,
  List<ConnectivityResult> connectivity = const [ConnectivityResult.wifi],
  MemoryFavoriteArtistsCache? cache,
  void Function()? onPickerOpened,
}) async {
  // 横向きではラージタイトルが出ないので、iPhone の縦向きで確かめる
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...favoriteArtistsOverrides(
          repository: repository,
          finder: FakeArtistArtworkFinder(const {}),
          connectivity: connectivity,
          cache: cache,
        ),
        recordsProvider.overrideWith((ref) => Stream.value(const [])),
        artistImagePickerProvider.overrideWithValue((context) async {
          onPickerOpened?.call();
          return pickedFile;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const FavoritesScreen(),
      ),
    ),
  );
  await _settle(tester);
}

/// 画面の動きが落ち着くまで進める。
///
/// 独自画像のあるお気に入りは、ネットワーク画像の読み込み中のスピナーが回り続けるので、
/// `pumpAndSettle` は終わらない。固定の時間だけ進める。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _openMenu(WidgetTester tester, String artistName) async {
  await tester.longPress(find.text(artistName));
  await _settle(tester);
}

List<FavoriteArtist> _favoritesOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(FavoritesScreen)),
    ).read(favoriteArtistsProvider).requireValue;

void main() {
  group('長押しのメニュー', () {
    testWidgets('独自画像がないときは、画像の変更とお気に入りから外すだけが出る', (tester) async {
      await _pumpScreen(
        tester,
        repository: FakeFavoriteArtistsRepository([
          favoriteArtist('1', 'Aimer'),
        ]),
      );

      await _openMenu(tester, 'Aimer');

      expect(find.text('画像を変更'), findsOneWidget);
      expect(find.text('元の写真に戻す'), findsNothing);
      expect(find.text('お気に入りから外す'), findsOneWidget);
    });

    testWidgets('独自画像があるときは、元の写真に戻すも出る', (tester) async {
      await _pumpScreen(
        tester,
        repository: FakeFavoriteArtistsRepository([
          favoriteArtist('1', 'Aimer', customImageUrl: _storedCustomImage),
        ]),
      );

      await _openMenu(tester, 'Aimer');

      expect(find.text('元の写真に戻す'), findsOneWidget);
    });

    testWidgets('オフラインでは、長押ししてもメニューを出さない', (tester) async {
      // オフラインのお気に入りは、端末のキャッシュから読む
      final cache = MemoryFavoriteArtistsCache()
        ..saved['u1'] = [favoriteArtist('1', 'Aimer').toJson()];
      await _pumpScreen(
        tester,
        repository: FakeFavoriteArtistsRepository(const []),
        cache: cache,
        connectivity: const [ConnectivityResult.none],
      );

      await _openMenu(tester, 'Aimer');

      expect(find.text('画像を変更'), findsNothing);
    });
  });

  group('画像を変更', () {
    testWidgets('選んだ画像をアップロードして保存し、表示を更新する', (tester) async {
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist('1', 'Aimer'),
        favoriteArtist('2', 'YOASOBI'),
      ]);
      await _pumpScreen(
        tester,
        repository: repository,
        pickedFile: File('/tmp/cropped.jpg'),
      );

      await _openMenu(tester, 'YOASOBI');
      await tester.tap(find.text('画像を変更'));
      await _settle(tester);

      expect(repository.uploads, [
        (userId: 'u1', favoriteId: '2', path: '/tmp/cropped.jpg'),
      ]);
      expect(repository.customImageUpdates, [('2', fakeUploadedImageUrl)]);
      expect(_favoritesOf(tester).map((f) => f.customImageUrl), [
        null,
        fakeUploadedImageUrl,
      ]);
      // 進行中の表示は閉じている
      expect(find.byKey(blockingProgressKey), findsNothing);
    });

    testWidgets('画像を選ばずにキャンセルしたら、何も変えない', (tester) async {
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist('1', 'Aimer'),
      ]);
      var pickerOpened = false;
      await _pumpScreen(
        tester,
        repository: repository,
        onPickerOpened: () => pickerOpened = true,
      );

      await _openMenu(tester, 'Aimer');
      await tester.tap(find.text('画像を変更'));
      await _settle(tester);

      expect(pickerOpened, isTrue);
      expect(repository.uploads, isEmpty);
      expect(repository.customImageUpdates, isEmpty);
    });

    testWidgets('保存に失敗しても、進行中の表示を閉じて、画面を操作できる', (tester) async {
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist('1', 'Aimer'),
      ])..failSetCustomImage = true;
      await _pumpScreen(
        tester,
        repository: repository,
        pickedFile: File('/tmp/cropped.jpg'),
      );

      await _openMenu(tester, 'Aimer');
      await tester.tap(find.text('画像を変更'));
      await _settle(tester);

      expect(find.byKey(blockingProgressKey), findsNothing);
      expect(find.text('Aimer'), findsOneWidget);
      // アップロードした画像は消している
      expect(repository.deletedImages, [fakeUploadedImageUrl]);
      // もう一度メニューを開ける
      await _openMenu(tester, 'Aimer');
      expect(find.text('画像を変更'), findsOneWidget);
    });
  });

  group('元の写真に戻す・お気に入りから外す', () {
    testWidgets('元の写真に戻すと、独自画像を外して Storage の画像を消す', (tester) async {
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist('1', 'Aimer', customImageUrl: _storedCustomImage),
      ]);
      await _pumpScreen(tester, repository: repository);

      await _openMenu(tester, 'Aimer');
      await tester.tap(find.text('元の写真に戻す'));
      await _settle(tester);

      expect(repository.customImageUpdates, [('1', null)]);
      expect(repository.deletedImages, [_storedCustomImage]);
      expect(find.byKey(blockingProgressKey), findsNothing);
    });

    testWidgets('お気に入りから外すと、そのお気に入りを削除する', (tester) async {
      final repository = FakeFavoriteArtistsRepository([
        favoriteArtist('1', 'Aimer'),
        favoriteArtist('2', 'YOASOBI'),
      ]);
      await _pumpScreen(tester, repository: repository);

      await _openMenu(tester, 'Aimer');
      await tester.tap(find.text('お気に入りから外す'));
      await _settle(tester);

      expect(repository.removedIds, ['1']);
      expect(find.text('Aimer'), findsNothing);
      expect(find.text('YOASOBI'), findsOneWidget);
    });
  });
}
