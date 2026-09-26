import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/japanese_date_format.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_actions.dart';
import 'package:recolle/features/records/record_calendar.dart';

/// 月のカレンダー。記録のある日に印を付け、選んだ日の記録を下に並べる。
class RecordCalendarView extends HookWidget {
  const RecordCalendarView({super.key, required this.records, this.today});

  final List<Record> records;

  /// テスト用に「今日」を差し替える。
  final DateTime? today;

  static const _weekdays = ['日', '月', '火', '水', '木', '金', '土'];

  @override
  Widget build(BuildContext context) {
    final todayDay = dayOf(today ?? DateTime.now());
    final month = useState(DateTime(todayDay.year, todayDay.month));
    final selected = useState(todayDay);
    final byDay = useMemoized(() => recordsByDay(records), [records]);
    final colors = context.colors;

    void moveMonth(int delta) {
      HapticFeedback.selectionClick();
      month.value = DateTime(month.value.year, month.value.month + delta);
    }

    final selectedRecords = byDay[selected.value] ?? const <Record>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
          child: Row(
            children: [
              Text(
                '${month.value.year}年${month.value.month}月',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              if (month.value != DateTime(todayDay.year, todayDay.month))
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: () {
                    month.value = DateTime(todayDay.year, todayDay.month);
                    selected.value = todayDay;
                  },
                  child: Text(
                    '今日',
                    style: TextStyle(fontSize: 15, color: colors.accent),
                  ),
                ),
              NavBarIconButton(
                icon: CupertinoIcons.chevron_left,
                semanticLabel: '前の月',
                onPressed: () => moveMonth(-1),
              ),
              NavBarIconButton(
                icon: CupertinoIcons.chevron_right,
                semanticLabel: '次の月',
                onPressed: () => moveMonth(1),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final (i, w) in _weekdays.indexed)
                Expanded(
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: i == 0 || i == 6
                          ? colors.textSecondary
                          : colors.textDisabled,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          // 横スワイプでも月を送れるようにする
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() < 200) return;
            moveMonth(v < 0 ? 1 : -1);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.9,
              children: [
                for (final day in monthGrid(
                  month.value.year,
                  month.value.month,
                ))
                  day == null
                      ? const SizedBox.shrink()
                      : _DayCell(
                          day: day,
                          records: byDay[day] ?? const [],
                          isToday: day == todayDay,
                          isSelected: day == selected.value,
                          onTap: () => selected.value = day,
                        ),
              ],
            ),
          ),
        ),
        InsetGroupedSection(
          header: formatJapaneseDate(selected.value, includeWeekday: true),
          hasLeading: false,
          children: [
            if (selectedRecords.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Text(
                  'この日の記録はありません',
                  style: TextStyle(fontSize: 15, color: colors.textSecondary),
                ),
              )
            else
              for (final r in selectedRecords)
                MediaListTile(
                  title: r.title,
                  subtitle: [
                    r.artistOrAuthor,
                    if (r.startTime != null)
                      '${r.startTime!.format()} ${r.type.startTimeLabel}',
                    ?r.venue,
                  ].join('・'),
                  trailing: Text(
                    r.type.japaneseLabel,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  onTap: () => openRecordDetail(context, r),
                ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.records,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final List<Record> records;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasLive = records.any((r) => r.type == RecordType.live);
    final Color background;
    final Color foreground;
    if (isSelected) {
      background = colors.accent;
      foreground = colors.onAccent;
    } else if (hasLive) {
      background = colors.accent.withValues(alpha: 0.18);
      foreground = colors.accent;
    } else {
      background = const Color(0x00000000);
      foreground = colors.textPrimary;
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${day.month}月${day.day}日${records.isEmpty ? '' : '、記録${records.length}件'}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
                border: isToday && !isSelected
                    ? Border.all(color: colors.accent, width: 1.5)
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: AppFonts.monoStyle(
                  fontSize: 15,
                  color: foreground,
                  fontWeight: records.isEmpty
                      ? FontWeight.w500
                      : FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final r in records.take(3))
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: r.type == RecordType.live
                            ? colors.accent
                            : colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
