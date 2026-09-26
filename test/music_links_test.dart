import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/features/music/music_links.dart';

void main() {
  group('StreamingService.link', () {
    test('Apple Music は正規 URL があればそれを使う', () {
      final direct = Uri.parse(
        'https://music.apple.com/jp/song/idol/1680000000',
      );
      expect(
        StreamingService.appleMusic.link(query: 'アイドル', directUrl: direct),
        direct,
      );
    });

    test('正規 URL がなければ各サービスの検索 URL になる', () {
      expect(
        StreamingService.appleMusic.link(query: 'アイドル YOASOBI').toString(),
        'https://music.apple.com/jp/search?term=%E3%82%A2%E3%82%A4%E3%83%89%E3%83%AB+YOASOBI',
      );
      expect(
        StreamingService.spotify.link(query: 'Mrs. GREEN APPLE').toString(),
        'https://open.spotify.com/search/Mrs.%20GREEN%20APPLE',
      );
      expect(
        StreamingService.spotify.link(query: 'AC/DC').toString(),
        'https://open.spotify.com/search/AC%2FDC',
      );
      expect(
        StreamingService.youtubeMusic.link(query: 'A&B').toString(),
        'https://music.youtube.com/search?q=A%26B',
      );
    });
  });

  group('setlistContainsSong', () {
    test('表記ゆれを除いて行単位で一致する', () {
      const setlist = 'アイドル\n夜に駆ける\nUNDEAD';
      expect(setlistContainsSong(setlist, '夜に 駆ける'), isTrue);
      expect(setlistContainsSong(setlist, 'undead'), isTrue);
    });

    test('部分一致や空のセトリでは一致しない', () {
      expect(setlistContainsSong('夜に駆ける', '夜に'), isFalse);
      expect(setlistContainsSong(null, 'アイドル'), isFalse);
      expect(setlistContainsSong('アイドル', ''), isFalse);
    });
  });
}
