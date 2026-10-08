import 'package:flutter/foundation.dart';

/// セトリの 1 行の種類。
enum SetlistEntryKind { song, section, mc }

/// セトリの区切りの名前。
abstract final class SetlistSections {
  SetlistSections._();

  static const rehearsal = 'リハ';
  static const main = '本番';
  static const encore = 'アンコール';
}

/// セトリの 1 行。保存はこれまでどおり改行区切りのテキストで、区切りは `--- アンコール ---`、
/// MC は `MC` の行として持つ（DB の形を変えずに、ほかのアプリの書式とも互換にするため）。
@immutable
class SetlistEntry {
  const SetlistEntry._(this.kind, this.label);

  const SetlistEntry.song(String title) : this._(SetlistEntryKind.song, title);
  const SetlistEntry.section(String name)
    : this._(SetlistEntryKind.section, name);
  static const mc = SetlistEntry._(SetlistEntryKind.mc, 'MC');

  factory SetlistEntry.parse(String line) {
    final text = line.trim();
    final section = _sectionPattern.firstMatch(text)?.group(1)?.trim();
    if (section != null && section.isNotEmpty) {
      return SetlistEntry.section(section);
    }
    if (text.toUpperCase() == 'MC' || text == 'ＭＣ') return mc;
    return SetlistEntry.song(text);
  }

  static final _sectionPattern = RegExp(r'^-{3,}\s*(.+?)\s*-{3,}$');

  final SetlistEntryKind kind;

  /// 曲名、または区切りの名前（「アンコール」など）。MC では `MC`。
  final String label;

  bool get isSong => kind == SetlistEntryKind.song;

  /// 保存する 1 行。
  String get line => switch (kind) {
    SetlistEntryKind.song => label,
    SetlistEntryKind.section => '--- $label ---',
    SetlistEntryKind.mc => 'MC',
  };

  @override
  bool operator ==(Object other) =>
      other is SetlistEntry && other.kind == kind && other.label == label;

  @override
  int get hashCode => Object.hash(kind, label);
}

/// セトリの行から曲名だけを取り出す（区切り・MC を除く）。
List<String> setlistSongTitles(Iterable<String> lines) => [
  for (final line in lines)
    if (SetlistEntry.parse(line).isSong) line.trim(),
];

/// 貼り付けや setlist.fm などから来た複数行のセトリを、保存用の行に整える。
///
/// - 空行は除く。
/// - 全曲に「1.」「01」「M1」「①」などの番号が付いていれば取り除く（曲名が数字で始まる
///   だけの 1 行を誤って削らないよう、全曲に付いているときだけ）。
/// - 「アンコール」「【本編】」「EN」などの見出し行は区切りに、「EN1 曲名」のような
///   アンコールの番号は、最初の 1 曲の前にアンコールの区切りを入れて番号を取る。
List<String> parsePastedSetlist(String text) {
  final raw = [
    for (final line in text.split(RegExp(r'\r\n|\r|\n')))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  final entries = <SetlistEntry>[];
  final songLines = <int>[];
  var encoreStarted = false;
  for (final line in raw) {
    final heading = _headingSection(line);
    if (heading != null) {
      entries.add(SetlistEntry.section(heading));
      if (heading.contains(SetlistSections.encore)) encoreStarted = true;
      continue;
    }
    final parsed = SetlistEntry.parse(line);
    if (!parsed.isSong) {
      entries.add(parsed);
      continue;
    }
    final encore = _encoreNumber.firstMatch(line);
    if (encore != null) {
      if (!encoreStarted) {
        entries.add(const SetlistEntry.section(SetlistSections.encore));
        encoreStarted = true;
      }
      entries.add(SetlistEntry.song(line.substring(encore.end).trim()));
      continue;
    }
    songLines.add(entries.length);
    entries.add(parsed);
  }

  final numbered =
      songLines.length >= 2 &&
      songLines.every((i) => _songNumber.hasMatch(entries[i].label));
  if (numbered) {
    for (final i in songLines) {
      entries[i] = SetlistEntry.song(
        entries[i].label.replaceFirst(_songNumber, '').trim(),
      );
    }
  }
  return [
    for (final e in entries)
      if (!e.isSong || e.label.isNotEmpty) e.line,
  ];
}

/// 行頭の曲番号。「1.」「01 」「M1」「M-1:」「①」など。区切り記号か空白が続くものだけ。
final _songNumber = RegExp(
  r'^(?:(?:[Mm]\s*-?\s*)?\d{1,3}(?:\s*[.．:：)）、]\s*|\s+)|[\u2460-\u2473]\s*)',
);

/// 「EN1 曲名」「EN-2. 曲名」のようなアンコールの曲番号。
final _encoreNumber = RegExp(
  r'^(?:EN|En|en|ＥＮ)\s*-?\s*\d{1,2}(?:\s*[.．:：)）、]\s*|\s+)',
);

/// 見出しとみなす行（括弧や記号で囲んだものも含む）の区切り名。当てはまらなければ null。
String? _headingSection(String line) {
  final inner = line
      .replaceAll(RegExp(r'^[\s\-ー―─〜~＝=【\[［<＜《『「(（*＊・■◆●]+'), '')
      .replaceAll(RegExp(r'[\s\-ー―─〜~＝=】\]］>＞》』」)）*＊:：]+$'), '')
      .trim();
  final decorated = inner != line.trim();
  final isHeading = decorated
      ? _headings.hasMatch(inner)
      : _unambiguousHeadings.hasMatch(inner);
  return isHeading ? _headingName(inner) : null;
}

final _headings = RegExp(
  r'^(?:ENCORE|Encore|encore|EN|ＥＮ|W\s*アンコール|Ｗアンコール|ダブルアンコール|'
  r'アンコール\s*\d*|本編|本番|リハ|リハーサル)$',
);

/// 囲みがなくても見出しとみなすもの。「アンコール」（YOASOBI）や「Encore」のように
/// 同名の曲があるものは、囲まれているときだけ見出しにする。
final _unambiguousHeadings = RegExp(
  r'^(?:ENCORE|EN|ＥＮ|W\s*アンコール|Ｗアンコール|ダブルアンコール|本編|リハーサル)$',
);

String _headingName(String heading) {
  final upper = heading.toUpperCase();
  if (upper == 'ENCORE' || upper == 'EN' || heading == 'ＥＮ') {
    return SetlistSections.encore;
  }
  if (heading == '本編') return SetlistSections.main;
  if (heading == 'リハーサル') return SetlistSections.rehearsal;
  return heading.replaceAll(RegExp(r'\s+'), '');
}
