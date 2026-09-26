import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/records/ticket_mail_parser.dart';

void main() {
  final now = DateTime(2026, 9, 27);

  test('e+ の当選メールから公演名・出演者・公演日・取得元を読み取る', () {
    const mail = '''
山田 太郎 様

イープラスをご利用いただきありがとうございます。
抽選の結果、チケットをご用意できましたのでお知らせします。

■公演名：Mrs. GREEN APPLE ARENA TOUR 2026 "BABEL no TOH"
■出演者：Mrs. GREEN APPLE
■公演日時：２０２６年１１月３日(火・祝) 17:00開場／18:00開演
■会場：さいたまスーパーアリーナ
■お支払期限：2026年10月1日(木) 23:59
''';
    final info = parseTicketMail(mail, now: now);
    expect(info.title, 'Mrs. GREEN APPLE ARENA TOUR 2026 "BABEL no TOH"');
    expect(info.artist, 'Mrs. GREEN APPLE');
    expect(info.date, DateTime(2026, 11, 3));
    expect(info.ticketSource, 'e+');
  });

  test('ローチケの【ラベル】形式や、値が次の行にある形式も読み取る', () {
    const mail = '''
ローソンチケットです。お申込み内容をご確認ください。

【公演名】
YOASOBI DOME LIVE 2026
【アーティスト】
YOASOBI
【公演日】
2026/05/03(日)
''';
    final info = parseTicketMail(mail, now: now);
    expect(info.title, 'YOASOBI DOME LIVE 2026');
    expect(info.artist, 'YOASOBI');
    expect(info.date, DateTime(2026, 5, 3));
    expect(info.ticketSource, 'ローチケ');
  });

  test('年のない公演日は、過ぎて半年以上なら翌年とみなす', () {
    expect(
      parseTicketMail('公演日：12月24日(木)', now: now).date,
      DateTime(2026, 12, 24),
    );
    expect(
      parseTicketMail('公演日：2月14日(日)', now: now).date,
      DateTime(2027, 2, 14),
    );
  });

  test('公演日ラベルのない日付（支払期限など）は公演日として拾わない', () {
    final info = parseTicketMail(
      'チケットぴあ\nお支払期限：2026年10月1日\n受付番号：123',
      now: now,
    );
    expect(info.date, isNull);
    expect(info.ticketSource, 'チケットぴあ');
  });

  test('存在しない日付は無視する', () {
    expect(parseTicketMail('公演日：2026年2月30日', now: now).date, isNull);
  });

  test('「公演日程のご案内」のような文中の語はラベルとして扱わない', () {
    final info = parseTicketMail('公演日程のご案内です。\n公演日: 2026.8.10', now: now);
    expect(info.date, DateTime(2026, 8, 10));
  });

  test('関係のない文章からは何も読み取らない', () {
    expect(parseTicketMail('こんにちは。明日の予定です。', now: now).isEmpty, isTrue);
  });
}
