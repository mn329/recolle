import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/japanese_date_format.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_actions.dart';
import 'package:recolle/features/records/record_timeline.dart';

/// 次の公演までを秒単位でカウントダウンするカード。タップで詳細を開く。
class NextEventCard extends StatefulWidget {
  const NextEventCard({super.key, required this.record, this.clock});

  final Record record;

  /// テスト用に現在時刻を差し替える。
  final DateTime Function()? clock;

  @override
  State<NextEventCard> createState() => _NextEventCardState();
}

class _NextEventCardState extends State<NextEventCard> {
  Timer? _timer;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final record = widget.record;
    final countdown = Countdown.between(record, _now());
    final details = [
      formatJapaneseDate(record.date, includeWeekday: true),
      if (record.startTime != null) '${record.startTime!.format()} 開演',
      ?record.venue,
    ].join('・');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        pressedOpacity: 0.8,
        onPressed: () => openRecordDetail(context, record),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '次の${record.type == RecordType.live ? '公演' : '予定'}まで',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.accent,
                ),
              ),
              const SizedBox(height: 6),
              Semantics(
                liveRegion: false,
                child: switch (countdown) {
                  CountdownToday() => Text(
                    '今日',
                    style: AppFonts.displayStyle(
                      fontSize: 40,
                      color: colors.accent,
                    ),
                  ),
                  CountdownRemaining(:final days, :final clock) => Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      if (days > 0) ...[
                        Text(
                          '$days',
                          style: AppFonts.displayStyle(
                            fontSize: 44,
                            color: colors.accent,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '日',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Text(
                        clock,
                        style: AppFonts.monoStyle(
                          fontSize: days > 0 ? 18 : 34,
                          color: days > 0
                              ? colors.textSecondary
                              : colors.accent,
                        ),
                      ),
                    ],
                  ),
                },
              ),
              const SizedBox(height: 10),
              Text(
                record.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${record.artistOrAuthor}　$details',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
