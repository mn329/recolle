/// ローマ字（ヘボン式・訓令式の混在も許す）をひらがなにする。
///
/// setlist.fm の曲名は、日本語の曲でもローマ字（例: "Kaze to Machi"）で登録されがち。
/// iTunes の検索はひらがなの読みで日本語の曲名を引けるので、その検索語を作るのに使う。
///
/// 英語の曲名（"Columbus" など）を無理に変換して別の語にしないよう、すべての文字が
/// ひらがなにできたときだけ返す。変換できない文字が残るなら null。
String? romajiToHiragana(String input) {
  final text = input
      .toLowerCase()
      .replaceAll('ā', 'aa')
      .replaceAll('ī', 'ii')
      .replaceAll('ū', 'uu')
      .replaceAll('ē', 'ee')
      .replaceAll('ō', 'ou')
      // 空白・ハイフン・アポストロフィ（n' の区切りは下で扱う）
      .replaceAll(RegExp(r"[\s\-_.・]"), '');
  if (text.isEmpty || !RegExp(r"^[a-z']+$").hasMatch(text)) return null;

  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (c == "'") {
      i++;
      continue;
    }

    // ん: 「n」の次が母音・y 以外、または語末。「n'」「nn」も ん
    if (c == 'n') {
      final next = i + 1 < text.length ? text[i + 1] : '';
      final isVowelOrY = next.isNotEmpty && 'aiueoy'.contains(next);
      if (next == "'") {
        out.write('ん');
        i += 2;
        continue;
      }
      if (next.isEmpty || !isVowelOrY) {
        // 「nn + 母音」は 1 つ目だけ ん（kinnen）。「nn」のあとが母音でなければ 2 つとも ん
        out.write('ん');
        i +=
            next == 'n' &&
                !(i + 2 < text.length && 'aiueoy'.contains(text[i + 2]))
            ? 2
            : 1;
        continue;
      }
    }

    // 促音: 同じ子音が続く（kk, tt, pp, ss…。n は除く）。「tch」は っち
    if (c != 'n' && !'aiueo'.contains(c) && i + 1 < text.length) {
      if (text[i + 1] == c) {
        out.write('っ');
        i++;
        continue;
      }
      if (c == 't' && text.startsWith('tch', i)) {
        out.write('っ');
        i++;
        continue;
      }
    }

    String? matched;
    var length = 0;
    for (final size in const [3, 2, 1]) {
      if (i + size > text.length) continue;
      final kana = _table[text.substring(i, i + size)];
      if (kana != null) {
        matched = kana;
        length = size;
        break;
      }
    }
    if (matched == null) return null;
    out.write(matched);
    i += length;
  }
  final result = out.toString();
  return result.isEmpty ? null : result;
}

/// 検索に使う読みの候補。助詞の「は」「へ」「を」はローマ字で wa・e・o と書かれるので、
/// 単独の語として現れたときは、助詞にした読みを先に、そのままの読みを後に返す。
///
/// 例: "Boku wa Mada" → ["ぼくはまだ", "ぼくわまだ"]。ひらがなにできなければ空。
List<String> romajiReadings(String input) {
  final literal = romajiToHiragana(input);
  if (literal == null) return const [];
  const particles = {'wa': 'は', 'e': 'へ', 'o': 'を'};
  final tokens = input.trim().split(RegExp(r'\s+'));
  if (tokens.length < 2 ||
      !tokens.any((t) => particles.containsKey(t.toLowerCase()))) {
    return [literal];
  }
  final parts = <String>[];
  for (final token in tokens) {
    final kana = particles[token.toLowerCase()] ?? romajiToHiragana(token);
    if (kana == null) return [literal];
    parts.add(kana);
  }
  final withParticles = parts.join();
  return withParticles == literal ? [literal] : [withParticles, literal];
}

const _table = <String, String>{
  'a': 'あ',
  'i': 'い',
  'u': 'う',
  'e': 'え',
  'o': 'お',
  'ka': 'か',
  'ki': 'き',
  'ku': 'く',
  'ke': 'け',
  'ko': 'こ',
  'sa': 'さ',
  'shi': 'し',
  'si': 'し',
  'su': 'す',
  'se': 'せ',
  'so': 'そ',
  'ta': 'た',
  'chi': 'ち',
  'ti': 'ち',
  'tsu': 'つ',
  'tu': 'つ',
  'te': 'て',
  'to': 'と',
  'na': 'な',
  'ni': 'に',
  'nu': 'ぬ',
  'ne': 'ね',
  'no': 'の',
  'ha': 'は',
  'hi': 'ひ',
  'fu': 'ふ',
  'hu': 'ふ',
  'he': 'へ',
  'ho': 'ほ',
  'ma': 'ま',
  'mi': 'み',
  'mu': 'む',
  'me': 'め',
  'mo': 'も',
  'ya': 'や',
  'yu': 'ゆ',
  'yo': 'よ',
  'ra': 'ら',
  'ri': 'り',
  'ru': 'る',
  're': 'れ',
  'ro': 'ろ',
  'wa': 'わ',
  'wo': 'を',
  'ga': 'が',
  'gi': 'ぎ',
  'gu': 'ぐ',
  'ge': 'げ',
  'go': 'ご',
  'za': 'ざ',
  'ji': 'じ',
  'zi': 'じ',
  'zu': 'ず',
  'ze': 'ぜ',
  'zo': 'ぞ',
  'da': 'だ',
  'di': 'ぢ',
  'du': 'づ',
  'de': 'で',
  'do': 'ど',
  'ba': 'ば',
  'bi': 'び',
  'bu': 'ぶ',
  'be': 'べ',
  'bo': 'ぼ',
  'pa': 'ぱ',
  'pi': 'ぴ',
  'pu': 'ぷ',
  'pe': 'ぺ',
  'po': 'ぽ',
  'kya': 'きゃ',
  'kyu': 'きゅ',
  'kyo': 'きょ',
  'sha': 'しゃ',
  'shu': 'しゅ',
  'sho': 'しょ',
  'sya': 'しゃ',
  'syu': 'しゅ',
  'syo': 'しょ',
  'cha': 'ちゃ',
  'chu': 'ちゅ',
  'cho': 'ちょ',
  'tya': 'ちゃ',
  'tyu': 'ちゅ',
  'tyo': 'ちょ',
  'cya': 'ちゃ',
  'cyu': 'ちゅ',
  'cyo': 'ちょ',
  'nya': 'にゃ',
  'nyu': 'にゅ',
  'nyo': 'にょ',
  'hya': 'ひゃ',
  'hyu': 'ひゅ',
  'hyo': 'ひょ',
  'mya': 'みゃ',
  'myu': 'みゅ',
  'myo': 'みょ',
  'rya': 'りゃ',
  'ryu': 'りゅ',
  'ryo': 'りょ',
  'gya': 'ぎゃ',
  'gyu': 'ぎゅ',
  'gyo': 'ぎょ',
  'ja': 'じゃ',
  'ju': 'じゅ',
  'jo': 'じょ',
  'jya': 'じゃ',
  'jyu': 'じゅ',
  'jyo': 'じょ',
  'zya': 'じゃ',
  'zyu': 'じゅ',
  'zyo': 'じょ',
  'dya': 'ぢゃ',
  'dyu': 'ぢゅ',
  'dyo': 'ぢょ',
  'bya': 'びゃ',
  'byu': 'びゅ',
  'byo': 'びょ',
  'pya': 'ぴゃ',
  'pyu': 'ぴゅ',
  'pyo': 'ぴょ',
};
