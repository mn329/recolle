import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/yen_format.dart';
import 'package:recolle/features/records/models/record.dart';

enum ShareCardStyle {
  ticket('チケット'),
  receipt('レシート');

  const ShareCardStyle(this.label);

  final String label;
}

/// シェア画像の差し色。ツアーのテーマカラーやペンライトの色に合わせて選べるようにする。
enum ShareCardTheme {
  gold('ゴールド', Color(0xFFE6C88F), Color(0xFF8A6526)),
  rose('ローズ', Color(0xFFF4A9BC), Color(0xFFB0476A)),
  red('レッド', Color(0xFFFF8A80), Color(0xFFB3261E)),
  sky('スカイ', Color(0xFF9CCBF2), Color(0xFF2F6FA8)),
  mint('ミント', Color(0xFF9FDDBE), Color(0xFF2D7D5A)),
  lavender('ラベンダー', Color(0xFFC8B6F2), Color(0xFF6649A8)),
  silver('シルバー', Color(0xFFD9DCE1), Color(0xFF4A4F57));

  const ShareCardTheme(this.label, this.onDark, this.onLight);

  final String label;

  /// チケット（暗い地）に載せる色。
  final Color onDark;

  /// レシート（白い紙）に載せる色。明るい色のままだと読めないので濃くしてある。
  final Color onLight;
}

/// カードに載せる一覧（セトリ・出演者）の 1 区切り。
typedef ShareCardList = ({
  String heading,
  List<String> items,
  String unit,
  String countLabel,
});

/// SNS に貼るための記録の画像。端末の外観設定に左右されないよう配色は固定する。
class RecordShareCard extends StatelessWidget {
  const RecordShareCard({
    super.key,
    required this.record,
    required this.style,
    this.theme = ShareCardTheme.gold,
  });

  final Record record;
  final ShareCardStyle style;
  final ShareCardTheme theme;

  /// 画像の論理幅。3 倍で書き出すと 1080px になり、ストーリーズにちょうど合う。
  static const double width = 360;

  /// 1 つの一覧に載せる曲数の上限。これより多いと縦に長くなりすぎる。
  static const int maxSongs = 40;

  /// これより多い一覧は、チケットでは 2 段組み、レシートでは小さい字にして詰める。
  static const int compactThreshold = 12;

  /// 対バン・フェスは出演者（お目当てには ★）に続けて、お目当てのセトリも載せる。
  static List<ShareCardList> listsFor(Record record) {
    if (record.acts.isEmpty) {
      return [
        (
          heading: 'SETLIST',
          items: splitSetlist(record.setlist),
          unit: '曲',
          countLabel: 'SONGS',
        ),
      ];
    }
    return [
      (
        heading: 'LINEUP',
        items: [
          for (final a in record.acts)
            if (a.artist.trim().isNotEmpty)
              a.isMain ? '★ ${a.artist}' : a.artist,
        ],
        unit: '組',
        countLabel: 'ACTS',
      ),
      for (final a in record.acts)
        if (a.isMain && a.songs.isNotEmpty)
          (
            heading: 'SETLIST · ${a.artist}',
            items: a.songs,
            unit: '曲',
            countLabel: 'SONGS',
          ),
    ].where((l) => l.items.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final lists = listsFor(record);
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: width,
        child: switch (style) {
          ShareCardStyle.ticket => _TicketCard(
            record: record,
            lists: lists,
            color: theme.onDark,
          ),
          ShareCardStyle.receipt => _ReceiptCard(
            record: record,
            lists: lists,
            color: theme.onLight,
          ),
        },
      ),
    );
  }
}

String _date(Record record) {
  const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  String two(int n) => n.toString().padLeft(2, '0');
  final d = record.date;
  final first =
      '${d.year}.${two(d.month)}.${two(d.day)} ${weekdays[d.weekday - 1]}';
  if (!record.isMultiDay) return first;
  final l = record.lastDate;
  return '$first – ${two(l.month)}.${two(l.day)} ${weekdays[l.weekday - 1]}';
}

String _number(int i) => (i + 1).toString().padLeft(2, '0');

String _moreLabel(ShareCardList list, int shown) =>
    'ほか ${list.items.length - shown} ${list.unit}';

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.record,
    required this.lists,
    required this.color,
  });

  final Record record;
  final List<ShareCardList> lists;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const c = AppPalette.dark;
    final details = [
      ('DATE', _date(record)),
      if (record.openTime != null) ('OPEN', record.openTime!.format()),
      if (record.startTime != null) ('START', record.startTime!.format()),
      if (record.venue != null) ('VENUE', record.venue!),
      if (record.seat != null) ('SEAT', record.seat!),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        // 差し色を左上からうっすら滲ませ、色を選んだことが券面全体で分かるようにする
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(color.withValues(alpha: 0.16), c.card),
            c.card,
          ],
          stops: const [0, 0.55],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'RECOLLE',
                style: AppFonts.displayStyle(
                  fontSize: 16,
                  color: color,
                  letterSpacing: 3,
                ),
              ),
              const Spacer(),
              Text(
                record.type.name.toUpperCase(),
                style: AppFonts.monoStyle(fontSize: 11, color: c.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            record.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.titleStyle(
              fontSize: 28,
              color: color,
            ).copyWith(height: 1.05),
          ),
          const SizedBox(height: 6),
          Text(
            record.artistOrAuthor,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          _Dashes(color: c.ticketDivider),
          const SizedBox(height: 14),
          for (final (label, value) in details)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(
                      label,
                      style: AppFonts.monoStyle(fontSize: 11, color: color),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontFamily: AppFonts.body,
                        fontSize: 13,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (final list in lists) ...[
            const SizedBox(height: 10),
            _Dashes(color: c.ticketDivider),
            const SizedBox(height: 14),
            Text(
              list.heading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.monoStyle(fontSize: 11, color: color),
            ),
            const SizedBox(height: 8),
            _TicketList(
              list: list,
              numberColor: color.withValues(alpha: 0.8),
              textColor: c.textPrimary,
              moreColor: c.textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

/// チケットの曲目。多いときは字を小さくして 2 段に組み、なるべく多くの曲名を載せる。
class _TicketList extends StatelessWidget {
  const _TicketList({
    required this.list,
    required this.numberColor,
    required this.textColor,
    required this.moreColor,
  });

  final ShareCardList list;
  final Color numberColor;
  final Color textColor;
  final Color moreColor;

  @override
  Widget build(BuildContext context) {
    final shown = list.items.take(RecordShareCard.maxSongs).toList();
    final compact = shown.length > RecordShareCard.compactThreshold;
    final fontSize = compact ? 11.0 : 13.0;

    Widget row(int i) => Padding(
      padding: EdgeInsets.only(bottom: compact ? 3 : 4),
      child: Row(
        children: [
          SizedBox(
            width: compact ? 22 : 28,
            child: Text(
              _number(i),
              style: AppFonts.monoStyle(
                fontSize: fontSize - 1,
                color: numberColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              shown[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: fontSize,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );

    // 上から下へ読んでから右の段へ移る順に並べる
    final half = (shown.length + 1) ~/ 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [for (var i = 0; i < half; i++) row(i)],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [for (var i = half; i < shown.length; i++) row(i)],
                ),
              ),
            ],
          )
        else
          for (var i = 0; i < shown.length; i++) row(i),
        if (list.items.length > shown.length)
          Text(
            _moreLabel(list, shown.length),
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 12,
              color: moreColor,
            ),
          ),
      ],
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.record,
    required this.lists,
    required this.color,
  });

  final Record record;
  final List<ShareCardList> lists;
  final Color color;

  static const _paper = Color(0xFFFBFAF6);
  static const _ink = Color(0xFF1C1B19);
  static const _faded = Color(0xFF7A766E);

  @override
  Widget build(BuildContext context) {
    TextStyle mono(double size, {Color color = _ink}) =>
        AppFonts.monoStyle(fontSize: size, color: color);

    Widget line(String left, String right, {double size = 13}) => Padding(
      padding: EdgeInsets.only(bottom: size < 13 ? 2 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(size),
            ),
          ),
          const SizedBox(width: 12),
          Text(right, style: mono(size)),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: _paper,
        border: Border(top: BorderSide(color: color, width: 6)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'RECOLLE',
            textAlign: TextAlign.center,
            style: AppFonts.displayStyle(
              fontSize: 26,
              color: color,
              letterSpacing: 4,
            ),
          ),
          Text(
            'LIVE RECEIPT',
            textAlign: TextAlign.center,
            style: mono(11, color: _faded),
          ),
          const SizedBox(height: 16),
          Text(
            record.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          Text(
            record.artistOrAuthor,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 13,
              color: _ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            [
              _date(record),
              if (record.openTime != null) 'OPEN ${record.openTime!.format()}',
              if (record.startTime != null)
                'START ${record.startTime!.format()}',
            ].join('  '),
            textAlign: TextAlign.center,
            style: mono(12, color: _faded),
          ),
          if (record.venue != null)
            Text(
              record.venue!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 12,
                color: _faded,
              ),
            ),
          for (final list in lists) ...[
            const SizedBox(height: 14),
            _Dashes(color: color),
            const SizedBox(height: 12),
            if (lists.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  list.heading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(11, color: color),
                ),
              ),
            ..._receiptItems(list, line),
          ],
          const SizedBox(height: 8),
          const _Dashes(color: _faded),
          const SizedBox(height: 10),
          for (final list in lists)
            line(list.countLabel, '${list.items.length}'),
          if (record.seat != null) line('SEAT', record.seat!),
          if (record.ticketPrice != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(child: Text('TOTAL', style: mono(16))),
                  Text(formatYen(record.ticketPrice!), style: mono(16)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'THANK YOU FOR THE MEMORIES',
            textAlign: TextAlign.center,
            style: mono(10, color: _faded),
          ),
        ],
      ),
    );
  }

  /// レシートらしさを残すため 1 段のまま、多いときは字を小さくして詰める。
  static List<Widget> _receiptItems(
    ShareCardList list,
    Widget Function(String left, String right, {double size}) line,
  ) {
    final shown = list.items.take(RecordShareCard.maxSongs).toList();
    final size = shown.length > RecordShareCard.compactThreshold ? 11.0 : 13.0;
    return [
      for (final (i, item) in shown.indexed)
        line('${_number(i)} $item', '1', size: size),
      if (list.items.length > shown.length)
        line(_moreLabel(list, shown.length), '', size: size),
    ];
  }
}

class _Dashes extends StatelessWidget {
  const _Dashes({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 5.0;
        final count = (constraints.maxWidth / (dash * 2)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < count; i++)
              SizedBox(
                width: dash,
                height: 1,
                child: ColoredBox(color: color),
              ),
          ],
        );
      },
    );
  }
}
