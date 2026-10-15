import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';

const _auto = 'https://is1-ssl.mzstatic.com/image/auto.jpg';
const _custom =
    'https://example.supabase.co/storage/v1/object/public/ticket-images/u1/artist_1_1.jpg';

FavoriteArtist _artist({String? artworkUrl, String? customImageUrl}) =>
    FavoriteArtist(
      id: '1',
      name: 'Aimer',
      artworkUrl: artworkUrl,
      customImageUrl: customImageUrl,
      createdAt: DateTime(2026),
    );

void main() {
  group('displayArtworkUrl', () {
    test('独自画像があれば、自動取得の写真より優先する', () {
      final artist = _artist(artworkUrl: _auto, customImageUrl: _custom);

      expect(artist.displayArtworkUrl, _custom);
    });

    test('独自画像がなければ、今まで通り自動取得の写真を使う', () {
      final artist = _artist(artworkUrl: _auto);

      expect(artist.displayArtworkUrl, _auto);
    });

    test('どちらもなければ null（頭文字の表示になる）', () {
      expect(_artist().displayArtworkUrl, isNull);
    });
  });

  group('JSON', () {
    test('custom_image_url を読み書きする', () {
      final json = _artist(artworkUrl: _auto, customImageUrl: _custom).toJson();
      expect(json['custom_image_url'], _custom);

      final restored = FavoriteArtist.fromJson(json);
      expect(restored.customImageUrl, _custom);
      expect(restored.artworkUrl, _auto);
    });

    test('custom_image_url がない古いキャッシュも読める', () {
      final json = _artist(artworkUrl: _auto).toJson()
        ..remove('custom_image_url');

      expect(FavoriteArtist.fromJson(json).customImageUrl, isNull);
    });
  });

  group('copyWith', () {
    test('独自画像を設定できる', () {
      final next = _artist(artworkUrl: _auto).copyWith(customImageUrl: _custom);

      expect(next.customImageUrl, _custom);
      expect(next.artworkUrl, _auto);
    });

    test('独自画像を null に戻せる（自動取得の写真に戻す）', () {
      final next = _artist(
        artworkUrl: _auto,
        customImageUrl: _custom,
      ).copyWith(customImageUrl: null);

      expect(next.customImageUrl, isNull);
      expect(next.displayArtworkUrl, _auto);
    });

    test('独自画像を渡さなければ、今の独自画像を保つ', () {
      final next = _artist(
        artworkUrl: _auto,
        customImageUrl: _custom,
      ).copyWith(artworkUrl: 'https://img/new');

      expect(next.customImageUrl, _custom);
      expect(next.artworkUrl, 'https://img/new');
    });
  });
}
