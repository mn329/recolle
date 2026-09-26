import 'package:flutter/foundation.dart';

/// チケットの購入・当選メールから読み取れた項目。読み取れなかった項目は null。
@immutable
class TicketMailInfo {
  const TicketMailInfo({this.title, this.artist, this.date, this.ticketSource});

  final String? title;
  final String? artist;
  final DateTime? date;
  final String? ticketSource;

  bool get isEmpty =>
      title == null && artist == null && date == null && ticketSource == null;
}

/// e+・ローチケ・チケットぴあなどのメール本文を、端末内だけで読み取る。
///
/// 各社とも「公演名：」「【公演日時】」のようなラベル付きの行で書くので、
/// ラベルを手がかりに値を拾う。[now] は年が省略された日付の補完に使う。
TicketMailInfo parseTicketMail(String text, {DateTime? now}) {
  final lines = _normalize(text)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);

  final dateText = _valueFor(lines, _dateLabels);
  return TicketMailInfo(
    title: _cleanValue(_valueFor(lines, _titleLabels)),
    artist: _cleanValue(_valueFor(lines, _artistLabels)),
    date: dateText == null ? null : _parseDate(dateText, now ?? DateTime.now()),
    ticketSource: _detectSource(text),
  );
}

// 長いラベルを先に並べ、「公演」が「公演日」を横取りしないようにする
const _titleLabels = ['公演タイトル', '公演名', 'イベント名', '興行名', 'ツアー名'];
const _artistLabels = ['アーティスト名', 'アーティスト', '出演者', '出演'];
const _dateLabels = ['公演日時', '公演日', '開催日時', '開催日', '日時', '日程'];

/// メールの差出人や本文に出る表記と、取得元欄に入れる名前。
const _sources = [
  (['ローソンチケット', 'ローチケ', 'l-tike'], 'ローチケ'),
  (['チケットぴあ', 't.pia.jp', 'pia.jp'], 'チケットぴあ'),
  (['イープラス', 'eplus', 'e+'], 'e+'),
  (['チケットボード', 'ticket board', 'ticketboard'], 'チケットボード'),
  (['チケプラ', 'ticketplus', 'ticket plus'], 'チケプラ'),
  (['lineチケット', 'line ticket'], 'LINEチケット'),
  (['楽天チケット'], '楽天チケット'),
  (['zaiko'], 'ZAIKO'),
];

String _normalize(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      buffer.writeCharCode(rune - 0xFEE0);
    } else if (rune == 0x3000) {
      buffer.write(' ');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

final _decorations = RegExp(r'^[■□◆◇●○◎★☆▼▽▶►・※\-\s]+');
final _brackets = RegExp(r'[【】\[\]〔〕〈〉《》<>]');
final _separator = RegExp(r'^\s*[:：]?\s*');

/// ラベルに続く値を返す。値が次の行に書かれている形式にも対応する。
String? _valueFor(List<String> lines, List<String> labels) {
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i]
        .replaceFirst(_decorations, '')
        .replaceAll(_brackets, ' ')
        .trim();
    for (final label in labels) {
      if (!line.startsWith(label)) continue;
      final rest = line.substring(label.length);
      // 「公演日」に対する「公演日程のご案内」のような文中の一致は除く
      if (rest.isNotEmpty && !RegExp(r'^\s|^[:：]').hasMatch(rest)) continue;
      final value = rest.replaceFirst(_separator, '').trim();
      if (value.isNotEmpty) return value;
      if (i + 1 < lines.length) return lines[i + 1];
    }
  }
  return null;
}

String? _cleanValue(String? value) {
  if (value == null) return null;
  var cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  // 公演名そのものに含まれる引用符は残し、全体を囲む括弧だけ外す
  final wrapped = RegExp(r'^「(.*)」$|^『(.*)』$').firstMatch(cleaned);
  if (wrapped != null) {
    cleaned = (wrapped.group(1) ?? wrapped.group(2)!).trim();
  }
  return cleaned.isEmpty ? null : cleaned;
}

final _fullDate = RegExp(
  r'(20\d{2})\s*[年/.\-]\s*(\d{1,2})\s*[月/.\-]\s*(\d{1,2})',
);
final _monthDay = RegExp(r'(\d{1,2})\s*[月/]\s*(\d{1,2})\s*日?');

DateTime? _parseDate(String text, DateTime now) {
  final full = _fullDate.firstMatch(text);
  if (full != null) {
    return _validDate(
      int.parse(full.group(1)!),
      int.parse(full.group(2)!),
      int.parse(full.group(3)!),
    );
  }
  final md = _monthDay.firstMatch(text);
  if (md == null) return null;
  final month = int.parse(md.group(1)!);
  final day = int.parse(md.group(2)!);
  // 年のないメールは公演前に届くので、半年以上前になるなら翌年の公演とみなす
  final thisYear = _validDate(now.year, month, day);
  if (thisYear == null) return null;
  final cutoff = DateTime(now.year, now.month - 6, now.day);
  return thisYear.isBefore(cutoff)
      ? _validDate(now.year + 1, month, day)
      : thisYear;
}

DateTime? _validDate(int year, int month, int day) {
  final date = DateTime(year, month, day);
  // DateTime は 2/30 などを翌月に繰り越すので、そのまま戻るかで妥当性を判定する
  if (date.month != month || date.day != day) return null;
  return date;
}

String? _detectSource(String text) {
  final lower = _normalize(text).toLowerCase();
  for (final (keywords, name) in _sources) {
    if (keywords.any(lower.contains)) return name;
  }
  return null;
}
