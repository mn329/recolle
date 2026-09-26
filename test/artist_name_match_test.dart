import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/utils/artist_name_match.dart';

void main() {
  group('artistMatches', () {
    test('大文字小文字とスペースの違いを無視して一致する', () {
      expect(artistMatches('yoasobi', 'YOASOBI'), isTrue);
      expect(artistMatches('Mrs. GREEN APPLE', 'mrs.greenapple'), isTrue);
      expect(artistMatches('米津　玄師', '米津玄師'), isTrue);
    });

    test('対バン・コラボ表記の各要素と一致する', () {
      expect(artistMatches('King Gnu × millennium parade', 'King Gnu'), isTrue);
      expect(artistMatches('Aimer & milet', 'milet'), isTrue);
      expect(artistMatches('Ado feat. Vaundy', 'Vaundy'), isTrue);
      expect(artistMatches('ずっと真夜中でいいのに。、ヨルシカ', 'ヨルシカ'), isTrue);
    });

    test('短い名前が無関係な記録に部分一致しない', () {
      expect(artistMatches('Aimer', 'A'), isFalse);
      expect(artistMatches('RADWIMPS', 'RAD'), isFalse);
    });

    test('空のお気に入り名は何にも一致しない', () {
      expect(artistMatches('YOASOBI', ''), isFalse);
      expect(artistMatches('YOASOBI', '   '), isFalse);
    });
  });
}
