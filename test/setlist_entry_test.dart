import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/records/models/record.dart';

void main() {
  group('SetlistEntry.parse', () {
    test('--- で囲んだ行は区切り、MC は MC、それ以外は曲', () {
      expect(
        SetlistEntry.parse('--- アンコール ---'),
        const SetlistEntry.section('アンコール'),
      );
      expect(SetlistEntry.parse('mc'), SetlistEntry.mc);
      expect(SetlistEntry.parse('ＭＣ'), SetlistEntry.mc);
      expect(SetlistEntry.parse(' 夜に駆ける '), const SetlistEntry.song('夜に駆ける'));
    });

    test('保存する行に戻すと元の書式になる', () {
      expect(const SetlistEntry.section('リハ').line, '--- リハ ---');
      expect(SetlistEntry.mc.line, 'MC');
    });
  });

  test('setlistSongTitles は区切りと MC を除く', () {
    expect(
      setlistSongTitles(['--- リハ ---', '群青', 'MC', '--- 本番 ---', 'アイドル']),
      ['群青', 'アイドル'],
    );
  });

  test('RecordAct.songTitles と Record.songsBy は区切りと MC を曲に数えない', () {
    const act = RecordAct(
      artist: 'YOASOBI',
      songs: ['群青', 'MC', '--- アンコール ---', 'アイドル'],
    );
    expect(act.songTitles, ['群青', 'アイドル']);
  });

  group('parsePastedSetlist', () {
    test('全曲に付いた番号を取り、空行を除く', () {
      expect(parsePastedSetlist('1. 夜に駆ける\n\n02 群青\r\nM3: アイドル\n④ 怪物'), [
        '夜に駆ける',
        '群青',
        'アイドル',
        '怪物',
      ]);
    });

    test('番号の付いていない曲が混じるときは、数字で始まる曲名を削らない', () {
      expect(parsePastedSetlist('22 Twenty-Two\n群青'), ['22 Twenty-Two', '群青']);
    });

    test('見出しは区切りに、MC は MC の行にする', () {
      expect(parsePastedSetlist('【本編】\n群青\nMC\n-ENCORE-\nアイドル'), [
        '--- 本番 ---',
        '群青',
        'MC',
        '--- アンコール ---',
        'アイドル',
      ]);
    });

    test('EN1 のような番号の曲の前にアンコールの区切りを 1 つだけ入れる', () {
      expect(parsePastedSetlist('1. 群青\n2. 怪物\nEN1. アイドル\nEN2 夜に駆ける'), [
        '群青',
        '怪物',
        '--- アンコール ---',
        'アイドル',
        '夜に駆ける',
      ]);
    });

    test('囲みのない「アンコール」は同名の曲として残す', () {
      expect(parsePastedSetlist('群青\nアンコール'), ['群青', 'アンコール']);
      expect(parsePastedSetlist('群青\n＜アンコール＞\n怪物'), [
        '群青',
        '--- アンコール ---',
        '怪物',
      ]);
    });

    test('ほかのアプリの --- 区切りはそのまま使う', () {
      expect(
        parsePastedSetlist('--- リハ ---\n\n--- 本番 ---\n--- アンコール ---\nMC'),
        ['--- リハ ---', '--- 本番 ---', '--- アンコール ---', 'MC'],
      );
    });
  });
}
