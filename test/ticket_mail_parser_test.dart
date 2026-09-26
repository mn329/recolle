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
    expect(info.venue, 'さいたまスーパーアリーナ');
    expect(info.openTime?.format(), '17:00');
    expect(info.startTime?.format(), '18:00');
    expect(info.endTime, isNull);
  });

  test('座席・料金・開演ラベルを読み取る（合計金額より券面の料金を優先）', () {
    const mail = '''
チケットぴあ
公演名：ARENA TOUR
公演日：2026年7月20日(月)
開場/開演：16:30/17:30
会場名：横浜アリーナ
座席：アリーナ A5ブロック 12列 34番
料金：S席 ¥12,800
合計金額：14,080円
''';
    final info = parseTicketMail(mail, now: now);
    expect(info.openTime?.format(), '16:30');
    expect(info.startTime?.format(), '17:30');
    expect(info.venue, '横浜アリーナ');
    expect(info.seat, 'アリーナ A5ブロック 12列 34番');
    expect(info.ticketPrice, 12800);
  });

  test('「開場 17:00 開演 18:00」の並びや終演予定も読む', () {
    final info = parseTicketMail(
      '公演日時：2026年11月3日 開場 17:00 開演 18:00\n終演予定：20:30',
      now: now,
    );
    expect(info.openTime?.format(), '17:00');
    expect(info.startTime?.format(), '18:00');
    expect(info.endTime?.format(), '20:30');
  });

  test('「開演：18:00」だけの行からも開演を読む', () {
    expect(parseTicketMail('開演：18:00', now: now).startTime?.format(), '18:00');
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
