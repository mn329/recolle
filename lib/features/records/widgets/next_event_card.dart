import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/japanese_date_format.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_actions.dart';
import 'package:recolle/features/records/record_timeline.dart';
import 'package:recolle/features/records/widgets/event_countdown.dart';

/// 次の公演の開場・開演・終演までを秒単位でカウントダウンするカード。タップで詳細を開く。
class NextEventCard extends StatelessWidget {
  const NextEventCard({super.key, required this.record, this.clock});

  final Record record;

  /// テスト用に現在時刻を差し替える。
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final details = [
      formatJapaneseDateRange(
        record.date,
        record.endDate,
        includeWeekday: true,
      ),
      ?formatEventTimes(record),
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
              EventCountdown(record: record, isNext: true, clock: clock),
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
                [
                  if (record.artistOrAuthor.isNotEmpty) record.artistOrAuthor,
                  details,
                ].join('　'),
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
