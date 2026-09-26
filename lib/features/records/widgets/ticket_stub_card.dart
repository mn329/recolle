import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/yen_format.dart';
import 'package:recolle/features/records/models/record.dart';

/// 詳細画面の券面。日付と時刻を上に、会場・座席・料金を切り取り線の下に並べる。
class TicketStubCard extends StatelessWidget {
  const TicketStubCard({super.key, required this.record, this.now});

  final Record record;

  /// 「◯日前」の基準日。テスト用に差し替える。
  final DateTime? now;

  static const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = record.type;
    final times = [
      if (record.openTime != null) ('OPEN', '開場', record.openTime!),
      if (record.startTime != null)
        ('START', type.startTimeLabel, record.startTime!),
      if (record.endTime != null) ('END', type.endTimeLabel, record.endTime!),
    ];
    final venue = record.venue;
    final seat = record.seat;
    final price = record.ticketPrice;
    final source = record.ticketSource;
    final hasStub =
        venue != null || seat != null || price != null || source != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: colors.isDark ? 0.5 : 0.6),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.alphaBlend(
                        colors.accent.withValues(
                          alpha: colors.isDark ? 0.2 : 0.14,
                        ),
                        colors.card,
                      ),
                      colors.card,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DateBlock(record: record, now: now ?? DateTime.now()),
                    if (times.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      // 文字サイズを大きくしている端末でもはみ出さないよう折り返す
                      Wrap(
                        spacing: 20,
                        runSpacing: 12,
                        children: [
                          for (final (en, ja, time) in times)
                            _Field(
                              en: en,
                              ja: ja,
                              child: Text(
                                time.format(),
                                style: AppFonts.monoStyle(
                                  fontSize: 22,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (hasStub) ...[
                SizedBox(
                  height: 22,
                  child: CustomPaint(
                    painter: _PerforationPainter(
                      fill: colors.card,
                      hole: colors.background,
                      dash: colors.separator,
                    ),
                  ),
                ),
                ColoredBox(
                  color: colors.card,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (venue != null)
                          _Field(
                            en: 'VENUE',
                            ja: type.venueLabel ?? '会場',
                            child: Text(
                              venue,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                                height: 1.35,
                              ),
                            ),
                          ),
                        if (seat != null) ...[
                          if (venue != null) const SizedBox(height: 16),
                          _Field(
                            en: 'SEAT',
                            ja: '座席',
                            child: Text(
                              seat,
                              style: AppFonts.displayStyle(
                                fontSize: 26,
                                color: colors.accent,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                        if (price != null || source != null) ...[
                          if (venue != null || seat != null)
                            const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (price != null)
                                Expanded(
                                  child: _Field(
                                    en: 'PRICE',
                                    ja: type.priceLabel,
                                    child: Text(
                                      formatYen(price),
                                      style: AppFonts.monoStyle(
                                        fontSize: 17,
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              if (source != null)
                                Expanded(
                                  child: _Field(
                                    en: type == RecordType.book
                                        ? 'STORE'
                                        : 'VIA',
                                    ja: type.sourceLabel,
                                    child: Text(
                                      source,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.record, required this.now});

  final Record record;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final d = record.date;
    final date =
        '${d.year}.${d.month.toString().padLeft(2, '0')}.'
        '${d.day.toString().padLeft(2, '0')}';
    final daysAgo = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    return _Field(
      en: 'DATE',
      ja: record.type == RecordType.live ? '公演日' : '日付',
      trailing: daysAgo > 0 ? '$daysAgo日前' : null,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              date,
              style: AppFonts.displayStyle(
                fontSize: 40,
                color: colors.textPrimary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              TicketStubCard._weekdays[d.weekday - 1],
              style: AppFonts.monoStyle(fontSize: 15, color: colors.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// 英字の小見出しと和名を上に添えた券面の項目。
class _Field extends StatelessWidget {
  const _Field({
    required this.en,
    required this.ja,
    required this.child,
    this.trailing,
  });

  final String en;
  final String ja;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              en,
              style: AppFonts.monoStyle(
                fontSize: 11,
                color: colors.accent,
              ).copyWith(letterSpacing: 1.6),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                ja,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.fill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  trailing!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

/// 券面の切り取り線。両端を半円にくり抜き、間に破線を引く。
class _PerforationPainter extends CustomPainter {
  const _PerforationPainter({
    required this.fill,
    required this.hole,
    required this.dash,
  });

  final Color fill;
  final Color hole;
  final Color dash;

  static const _holeRadius = 11.0;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    canvas.drawRect(Offset.zero & size, Paint()..color = fill);
    final holePaint = Paint()..color = hole;
    canvas
      ..drawCircle(Offset(0, centerY), _holeRadius, holePaint)
      ..drawCircle(Offset(size.width, centerY), _holeRadius, holePaint);

    final dashPaint = Paint()
      ..color = dash
      ..strokeWidth = 1.2;
    const dashWidth = 6.0;
    const gap = 5.0;
    var x = _holeRadius + 8;
    while (x + dashWidth < size.width - _holeRadius - 8) {
      canvas.drawLine(
        Offset(x, centerY),
        Offset(x + dashWidth, centerY),
        dashPaint,
      );
      x += dashWidth + gap;
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.hole != hole ||
      oldDelegate.dash != dash;
}
