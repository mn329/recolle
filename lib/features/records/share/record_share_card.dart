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

/// SNS に貼るための記録の画像。端末の外観設定に左右されないよう配色は固定する。
class RecordShareCard extends StatelessWidget {
  const RecordShareCard({super.key, required this.record, required this.style});

  final Record record;
  final ShareCardStyle style;

  /// 画像の論理幅。3 倍で書き出すと 1080px になり、ストーリーズにちょうど合う。
  static const double width = 360;

  /// 載せる曲数の上限。多いと縦に長くなりすぎる。
  static const int maxSongs = 12;

  List<String> get _songs => (record.setlist ?? '')
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: width,
        child: switch (style) {
          ShareCardStyle.ticket => _TicketCard(record: record, songs: _songs),
          ShareCardStyle.receipt => _ReceiptCard(record: record, songs: _songs),
        },
      ),
    );
  }
}

String _date(DateTime d) {
  const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}.${two(d.month)}.${two(d.day)} ${weekdays[d.weekday - 1]}';
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.record, required this.songs});

  final Record record;
  final List<String> songs;

  @override
  Widget build(BuildContext context) {
    const c = AppPalette.dark;
    final details = [
      ('DATE', _date(record.date)),
      if (record.startTime != null) ('START', record.startTime!.format()),
      if (record.venue != null) ('VENUE', record.venue!),
      if (record.seat != null) ('SEAT', record.seat!),
    ];
    final shown = songs.take(RecordShareCard.maxSongs).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.accent.withValues(alpha: 0.45)),
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
                  color: c.accent,
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
            style: AppFonts.displayStyle(
              fontSize: 34,
              color: c.accent,
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
                      style: AppFonts.monoStyle(fontSize: 11, color: c.accent),
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
          if (shown.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Dashes(color: c.ticketDivider),
            const SizedBox(height: 14),
            Text(
              'SETLIST',
              style: AppFonts.monoStyle(fontSize: 11, color: c.accent),
            ),
            const SizedBox(height: 8),
            for (final (i, song) in shown.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        (i + 1).toString().padLeft(2, '0'),
                        style: AppFonts.monoStyle(
                          fontSize: 12,
                          color: c.accent.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        song,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
            if (songs.length > shown.length)
              Text(
                'ほか ${songs.length - shown.length} 曲',
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 12,
                  color: c.textSecondary,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.record, required this.songs});

  final Record record;
  final List<String> songs;

  static const _paper = Color(0xFFFBFAF6);
  static const _ink = Color(0xFF1C1B19);
  static const _faded = Color(0xFF7A766E);

  @override
  Widget build(BuildContext context) {
    TextStyle mono(double size, {Color color = _ink}) =>
        AppFonts.monoStyle(fontSize: size, color: color);
    final shown = songs.take(RecordShareCard.maxSongs).toList();

    Widget line(String left, String right) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(13),
            ),
          ),
          const SizedBox(width: 12),
          Text(right, style: mono(13)),
        ],
      ),
    );

    return Container(
      color: _paper,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'RECOLLE',
            textAlign: TextAlign.center,
            style: AppFonts.displayStyle(
              fontSize: 26,
              color: _ink,
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
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          Text(
            record.artistOrAuthor,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 13,
              color: _ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            [
              _date(record.date),
              if (record.startTime != null) record.startTime!.format(),
            ].join('  '),
            textAlign: TextAlign.center,
            style: mono(12, color: _faded),
          ),
          if (record.venue != null)
            Text(
              record.venue!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 12,
                color: _faded,
              ),
            ),
          const SizedBox(height: 14),
          const _Dashes(color: _faded),
          const SizedBox(height: 12),
          for (final (i, song) in shown.indexed)
            line('${(i + 1).toString().padLeft(2, '0')} $song', '1'),
          if (songs.length > shown.length)
            line('ほか ${songs.length - shown.length} 曲', ''),
          if (songs.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _Dashes(color: _faded),
            const SizedBox(height: 10),
            line('SONGS', '${songs.length}'),
          ],
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
