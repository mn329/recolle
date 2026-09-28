import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_timeline.dart';

/// 開場・開演・終演までを秒単位で数える見出しと数字。1 秒ごとに描き直す。
class EventCountdown extends StatefulWidget {
  const EventCountdown({
    super.key,
    required this.record,
    this.isNext = false,
    this.clock,
  });

  final Record record;

  /// ホームの「次の公演」として出すなら true。見出しに「次の公演」を付ける。
  final bool isNext;

  /// テスト用に現在時刻を差し替える。
  final DateTime Function()? clock;

  @override
  State<EventCountdown> createState() => _EventCountdownState();
}

class _EventCountdownState extends State<EventCountdown> {
  Timer? _timer;

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

  String _heading(Countdown countdown) {
    final type = widget.record.type;
    final kind = type == RecordType.live ? '公演' : '予定';
    final next = widget.isNext ? '次の$kind' : '';
    return switch (countdown) {
      CountdownRemaining(target: CountdownTarget.end) =>
        '${type.inProgressLabel}・${type.endTimeLabel}まで',
      CountdownRemaining(:final target, hasTime: true) => [
        if (next.isNotEmpty) next,
        '${target.labelFor(type)}まで',
      ].join('・'),
      CountdownRemaining() ||
      CountdownToday() => '${next.isEmpty ? kind : next}まで',
      CountdownEnded() => '${type.endTimeLabel}しました',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final countdown = Countdown.between(
      widget.record,
      (widget.clock ?? DateTime.now)(),
    );
    final bigWord = AppFonts.displayStyle(fontSize: 40, color: colors.accent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _heading(countdown),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.accent,
          ),
        ),
        const SizedBox(height: 6),
        switch (countdown) {
          CountdownToday() => Text('今日', style: bigWord),
          CountdownEnded() => Text(
            widget.record.type.endTimeLabel,
            style: bigWord,
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
                  color: days > 0 ? colors.textSecondary : colors.accent,
                ),
              ),
            ],
          ),
        },
      ],
    );
  }
}
