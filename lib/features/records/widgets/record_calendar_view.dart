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

/// 月のカレンダーと、その月の記録の一覧。日を選ぶと一覧をその日に絞る。
class RecordCalendarView extends HookWidget {
  const RecordCalendarView({super.key, required this.records, this.today});

  final List<Record> records;

  /// テスト用に「今日」を差し替える。
  final DateTime? today;

  static const _weekdays = ['日', '月', '火', '水', '木', '金', '土'];
  static const double _rowHeight = 38;

  @override
  Widget build(BuildContext context) {
    final todayDay = dayOf(today ?? DateTime.now());
    final thisMonth = DateTime(todayDay.year, todayDay.month);
    final month = useState(thisMonth);
    final selected = useState<DateTime?>(null);
    final byDay = useMemoized(() => recordsByDay(records), [records]);
    final colors = context.colors;

    void showMonth(DateTime m) {
      month.value = m;
      selected.value = null;
    }

    void moveMonth(int delta) {
      HapticFeedback.selectionClick();
      showMonth(DateTime(month.value.year, month.value.month + delta));
    }

    final grid = monthGrid(month.value.year, month.value.month);
    final monthDays = grid.whereType<DateTime>().toList();
    final listedDays = selected.value != null
        ? [selected.value!]
        : [
            for (final d in monthDays)
              if (byDay.containsKey(d)) d,
          ];
    final monthCount = [for (final d in monthDays) ...?byDay[d]].length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox(width: 8),
                  Text(
                    '${month.value.year}年${month.value.month}月',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (month.value != thisMonth)
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                      onPressed: () => showMonth(thisMonth),
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
              Row(
                children: [
                  for (final w in _weekdays)
                    Expanded(
                      child: Text(
                        w,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.textDisabled,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              GestureDetector(
                // 横スワイプでも月を送れるようにする
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v.abs() < 200) return;
                  moveMonth(v < 0 ? 1 : -1);
                },
                child: Column(
                  children: [
                    for (var i = 0; i < grid.length; i += 7)
                      SizedBox(
                        height: _rowHeight,
                        child: Row(
                          children: [
                            for (final day in grid.sublist(i, i + 7))
                              Expanded(
                                child: day == null
                                    ? const SizedBox.shrink()
                                    : _DayCell(
                                        day: day,
                                        records: byDay[day] ?? const [],
                                        isToday: day == todayDay,
                                        isSelected: day == selected.value,
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          // もう一度押したら月全体の一覧に戻す
                                          selected.value = day == selected.value
                                              ? null
                                              : day;
                                        },
                                      ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _ListHeader(
          title: selected.value == null
              ? '${month.value.month}月の記録・$monthCount件'
              : formatJapaneseDate(selected.value!, includeWeekday: true),
          onShowAll: selected.value == null
              ? null
              : () => selected.value = null,
        ),
        if (listedDays.isEmpty ||
            (selected.value != null && !byDay.containsKey(selected.value)))
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              selected.value == null ? 'この月の記録はありません' : 'この日の記録はありません',
              style: TextStyle(fontSize: 15, color: colors.textSecondary),
            ),
          )
        else
          InsetGroupedSection(
            hasLeading: false,
            children: [
              for (final d in listedDays)
                for (final r in byDay[d]!)
                  MediaListTile(
                    leading: _DateBadge(day: d),
                    title: r.title,
                    subtitle: [
                      r.artistOrAuthor,
                      if (r.startTime != null)
                        '${r.startTime!.format()} ${r.type.startTimeLabel}',
                      ?r.venue,
                    ].join('・'),
                    onTap: () => openRecordDetail(context, r),
                  ),
            ],
          ),
      ],
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.title, this.onShowAll});

  final String title;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 16, 6),
      child: Row(
        children: [
          Expanded(child: Text(title, style: sectionHeaderTextStyle(context))),
          if (onShowAll != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 28),
              onPressed: onShowAll,
              child: Text(
                '月全体を表示',
                style: TextStyle(fontSize: 13, color: colors.accent),
              ),
            ),
        ],
      ),
    );
  }
}

/// 一覧の先頭に出す「日付と曜日」。
class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.day});

  final DateTime day;

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 34,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${day.day}',
            style: AppFonts.monoStyle(fontSize: 18, color: colors.accent),
          ),
          Text(
            _weekdays[day.weekday - 1],
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
        ],
      ),
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
    final hasRecords = records.isNotEmpty;
    final Color background;
    final Color foreground;
    if (isSelected) {
      background = colors.accent;
      foreground = colors.onAccent;
    } else if (hasRecords) {
      background = colors.accent.withValues(alpha: 0.2);
      foreground = colors.accent;
    } else {
      background = const Color(0x00000000);
      foreground = colors.textPrimary;
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${day.month}月${day.day}日${hasRecords ? '、記録${records.length}件' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Container(
            width: 32,
            height: 32,
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
                fontSize: 14,
                color: foreground,
                fontWeight: hasRecords ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
