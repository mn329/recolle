import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/utils/yen_format.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/record_stats.dart';

/// 参戦回数・チケット代・よく行ったアーティストなどを年ごとに振り返る画面。
class StatsScreen extends HookConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(recordsProvider);
    final selectedYear = useState<int?>(DateTime.now().year);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: LargeTitleScrollView(
        title: '振り返り',
        slivers: [
          recordsAsync.when(
            data: (records) {
              final now = DateTime.now();
              final years = yearsWithRecords(records, now);
              // 選択中の年に記録がなければ（年が明けた直後など）全期間にする
              final year = years.contains(selectedYear.value)
                  ? selectedYear.value
                  : null;
              final stats = computeStats(records, now: now, year: year);
              return SliverList.list(
                children: [
                  _YearChips(
                    years: years,
                    selected: year,
                    onSelected: (y) => selectedYear.value = y,
                  ),
                  if (stats.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: IosEmptyState(
                        icon: CupertinoIcons.chart_bar,
                        message: '行ったライブを記録すると、ここに集計が表示されます。',
                      ),
                    )
                  else ...[
                    _Summary(stats: stats),
                    _MonthlyChart(counts: stats.liveCountsByMonth),
                    _Ranking(header: 'よく行ったアーティスト', items: stats.topArtists),
                    _Ranking(header: 'よく行った会場', items: stats.topVenues),
                    _Ranking(header: 'よく聴いた曲', items: stats.topSongs),
                    SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
                  ],
                ],
              );
            },
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CupertinoActivityIndicator(radius: 14)),
            ),
            error: (error, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: IosEmptyState(
                icon: CupertinoIcons.exclamationmark_triangle,
                message: toUserFriendlyMessage(error),
                actionLabel: '再読み込み',
                onAction: () => ref.invalidate(recordsProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _YearChips extends StatelessWidget {
  const _YearChips({
    required this.years,
    required this.selected,
    required this.onSelected,
  });

  final List<int> years;
  final int? selected;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: years.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return CapsuleChip(
              label: 'すべて',
              selected: selected == null,
              onTap: () => onSelected(null),
            );
          }
          final year = years[index - 1];
          return CapsuleChip(
            label: '$year年',
            selected: selected == year,
            onTap: () => onSelected(year),
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.stats});

  final RecordStats stats;

  @override
  Widget build(BuildContext context) {
    final average = stats.averageTicketPrice;
    final others = [
      for (final t in RecordType.values)
        if (t != RecordType.live && stats.countsByType[t]! > 0)
          '${t.japaneseLabel} ${stats.countsByType[t]}',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'ライブ',
                  value: '${stats.liveCount}',
                  unit: '回',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'チケット代の合計',
                  value: formatYen(stats.totalTicketPrice),
                  caption: average == null
                      ? 'チケット代を入力すると集計されます'
                      : '平均 ${formatYen(average)}',
                ),
              ),
            ],
          ),
          if (others.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text(
                others.join('　'),
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.unit,
    this.caption,
  });

  final String label;
  final String value;
  final String? unit;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: AppFonts.displayStyle(
                    fontSize: 34,
                    color: colors.accent,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (caption != null)
            Text(
              caption!,
              maxLines: 2,
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// 月別のライブ数の棒グラフ。
class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.counts});

  final List<int> counts;

  static const double _barAreaHeight = 96;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final max = counts.fold(0, (a, b) => a > b ? a : b);
    return InsetGroupedSection(
      header: '月別のライブ',
      hasLeading: false,
      children: [
        Semantics(
          label: [
            for (final (i, c) in counts.indexed)
              if (c > 0) '${i + 1}月 $c回',
          ].join('、'),
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, c) in counts.indexed)
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c == 0 ? '' : '$c',
                          style: AppFonts.monoStyle(
                            fontSize: 10,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: max == 0
                              ? 2
                              : 2 + (_barAreaHeight - 2) * c / max,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: c == 0 ? colors.fill : colors.accent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Ranking extends StatelessWidget {
  const _Ranking({required this.header, required this.items});

  final String header;
  final List<RankedItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    return InsetGroupedSection(
      header: header,
      children: [
        for (final (i, item) in items.indexed)
          GroupedRow(
            leading: SizedBox(
              width: 24,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.center,
                style: AppFonts.monoStyle(fontSize: 15, color: colors.accent),
              ),
            ),
            title: item.label,
            additionalInfo: Text(
              '${item.count}回',
              style: TextStyle(fontSize: 15, color: colors.textSecondary),
            ),
          ),
      ],
    );
  }
}
