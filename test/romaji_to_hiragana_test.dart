import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/music/data/romaji_to_hiragana.dart';

void main() {
  test('日本語の曲名のローマ字を、ひらがなにする', () {
    expect(romajiToHiragana('Kaze to Machi'), 'かぜとまち');
    expect(romajiToHiragana('Gekijyo'), 'げきじょ');
    expect(romajiToHiragana('Sakura'), 'さくら');
    expect(romajiToHiragana('Hontou'), 'ほんとう');
    expect(romajiToHiragana('Matcha'), 'まっちゃ');
    expect(romajiToHiragana('Nippon'), 'にっぽん');
  });

  test('「ん」を正しく扱う（語末・子音の前・n\' ・nn）', () {
    expect(romajiToHiragana('Ken'), 'けん');
    expect(romajiToHiragana('Kinnen'), 'きんねん');
    expect(romajiToHiragana("Shin'ya"), 'しんや');
    expect(romajiToHiragana('Sanpo'), 'さんぽ');
  });

  test('ひらがなにできない英語の曲名は null にする', () {
    expect(romajiToHiragana('Columbus'), isNull);
    expect(romajiToHiragana('Lemon'), isNull);
    expect(romajiToHiragana('Soup'), isNull);
    expect(romajiToHiragana(''), isNull);
    expect(romajiToHiragana('夜に駆ける'), isNull);
  });
}
