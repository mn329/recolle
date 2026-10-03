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

  test('助詞（wa・e・o）は「は・へ・を」の読みを先に、そのままの読みを後に返す', () {
    expect(romajiReadings('Boku wa Mada'), ['ぼくはまだ', 'ぼくわまだ']);
    expect(romajiReadings('Haru e'), ['はるへ', 'はるえ']);
    expect(romajiReadings('Kimi o Sagashite'), ['きみをさがして', 'きみおさがして']);
  });

  test('助詞がなければ、そのままの読みだけを返し、変換できなければ空', () {
    expect(romajiReadings('Kaze to Machi'), ['かぜとまち']);
    expect(romajiReadings('Columbus'), isEmpty);
  });
}
