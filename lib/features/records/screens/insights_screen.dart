import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/utils/japanese_date_format.dart';
import 'package:recolle/core/utils/yen_format.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/favorite_artist_chips.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/record_actions.dart';
import 'package:recolle/features/records/record_stats.dart';
import 'package:recolle/features/records/record_timeline.dart';
import 'package:recolle/features/records/widgets/record_calendar_view.dart';

enum InsightsView {
  calendar('カレンダー'),
  stats('集計');

  const InsightsView(this.label);

  final String label;
}

/// 「振り返り」タブ。カレンダーと、年ごとの参戦回数・チケット代・ランキングを切り替える。
///
/// ホームと同じお気に入りアーティストのチップ（または集計のランキング）でアーティストを選ぶと、
/// カレンダーも集計もそのアーティストの記録だけになる。
class InsightsScreen extends HookConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(recordsProvider);
    final view = useState(InsightsView.calendar);
    final selectedYear = useState<int?>(DateTime.now().year);
    final selectedArtist = useState<String?>(null);
    final favorites =
        ref.watch(favoriteArtistsProvider).asData?.value ??
        const <FavoriteArtist>[];

    return Scaffold(
      backgroundColor: context.colors.background,
      body: LargeTitleScrollView(
        title: '振り返り',
        bottom: _InsightsFilterBar(
          view: view.value,
          onViewChanged: (v) => view.value = v,
          favorites: favorites,
          selectedArtist: selectedArtist.value,
          onArtistSelected: (a) => selectedArtist.value = a,
        ),
        onRefresh: () => ref.refresh(recordsProvider.future),
        contentKey: (view.value, selectedArtist.value),
        slivers: [
          recordsAsync.when(
            data: (records) {
              final artist = selectedArtist.value;
              final filtered = filterByArtist(records, artist);
              return SliverList.list(
                children: [
                  if (view.value == InsightsView.calendar)
                    RecordCalendarView(records: filtered)
                  else
                    ..._statsChildren(
                      context,
                      filtered,
                      selectedYear,
                      artist: artist,
                      onArtistSelected: (a) => selectedArtist.value = a,
                    ),
                  SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
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

  List<Widget> _statsChildren(
    BuildContext context,
    List<Record> records,
    ValueNotifier<int?> selectedYear, {
    required String? artist,
    required ValueChanged<String> onArtistSelected,
  }) {
    final now = DateTime.now();
    final years = yearsWithRecords(records, now);
    // 選択中の年に記録がなければ（年が明けた直後など）全期間にする
    final year = years.contains(selectedYear.value) ? selectedYear.value : null;
    final stats = computeStats(
      records,
      now: now,
      year: year,
      rankingLimit: artist == null ? 5 : 10,
    );
    final nextLive = artist == null
        ? null
        : splitByDate(
            records,
            now,
          ).upcoming.where((r) => r.type == RecordType.live).firstOrNull;
    return [
      if (years.length > 1)
        _ChipRow<int>(
          allLabel: 'すべての年',
          items: [for (final y in years) ('$y年', y)],
          selected: year,
          onSelected: (y) => selectedYear.value = y,
        ),
      if (stats.isEmpty && nextLive == null)
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: IosEmptyState(
            icon: CupertinoIcons.chart_bar,
            message: artist == null
                ? '行ったライブを記録すると、ここに集計が表示されます。'
                : '$artistのライブの記録はまだありません。',
          ),
        )
      else ...[
        _Summary(stats: stats),
        if (artist != null) _ArtistMilestones(stats: stats, nextLive: nextLive),
        if (artist == null) _MonthlyChart(counts: stats.liveCountsByMonth),
        if (artist == null)
          _Ranking(
            header: 'よく行ったアーティスト',
            items: stats.topArtists,
            onTap: onArtistSelected,
          ),
        _Ranking(header: 'よく聴いた曲', items: stats.topSongs),
        _Ranking(header: 'よく行った会場', items: stats.topVenues),
        if (artist != null) _History(lives: stats.lives),
      ],
    ];
  }
}

/// ナビゲーションバーの下に固定する、表示の切り替えとアーティストの絞り込み（ホームと同じチップ）。
class _InsightsFilterBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _InsightsFilterBar({
    required this.view,
    required this.onViewChanged,
    required this.favorites,
    required this.selectedArtist,
    required this.onArtistSelected,
  });

  final InsightsView view;
  final ValueChanged<InsightsView> onViewChanged;
  final List<FavoriteArtist> favorites;
  final String? selectedArtist;
  final ValueChanged<String?> onArtistSelected;

  static const double _segmentHeight = 48;

  bool get _showsChips =>
      FavoriteArtistChips.isVisible(favorites, selectedArtist);

  @override
  Size get preferredSize => Size.fromHeight(
    _segmentHeight + (_showsChips ? FavoriteArtistChips.height : 0),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _segmentHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: IosSegmentedControl<InsightsView>(
              value: view,
              segments: {for (final v in InsightsView.values) v: v.label},
              onChanged: onViewChanged,
            ),
          ),
        ),
        if (_showsChips)
          FavoriteArtistChips(
            favorites: favorites,
            selectedName: selectedArtist,
            onSelected: onArtistSelected,
          ),
      ],
    );
  }
}

/// 「すべて」と各項目を横に並べる絞り込みチップ。null が「すべて」。
class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.allLabel,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final String allLabel;
  final List<(String label, T value)> items;
  final T? selected;
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return CapsuleChip(
              label: allLabel,
              selected: selected == null,
              onTap: () => onSelected(null),
            );
          }
          final (label, value) = items[index - 1];
          return CapsuleChip(
            label: label,
            selected: selected == value,
            onTap: () => onSelected(value),
          );
        },
      ),
    );
  }
}

/// アーティストを選んだときの、初めて・最後に行った日と次の公演。
class _ArtistMilestones extends StatelessWidget {
  const _ArtistMilestones({required this.stats, required this.nextLive});

  final RecordStats stats;
  final Record? nextLive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget date(DateTime d) => Text(
      formatJapaneseDate(d, includeWeekday: true),
      style: AppFonts.monoStyle(fontSize: 15, color: colors.textSecondary),
    );
    final next = nextLive;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: InsetGroupedSection(
        hasLeading: false,
        children: [
          if (stats.firstLiveDate case final d?)
            GroupedRow(title: '初めて行った日', additionalInfo: date(d)),
          if (stats.lastLiveDate case final d?)
            GroupedRow(title: '最後に行った日', additionalInfo: date(d)),
          if (next != null)
            GroupedRow(
              title: '次の公演',
              subtitle: next.title,
              additionalInfo: date(next.date),
              onTap: () => openRecordDetail(context, next),
            ),
        ],
      ),
    );
  }
}

/// アーティストを選んだときの、行ったライブの一覧（新しい順）。
class _History extends StatelessWidget {
  const _History({required this.lives});

  final List<Record> lives;

  @override
  Widget build(BuildContext context) {
    if (lives.isEmpty) return const SizedBox.shrink();
    return InsetGroupedSection(
      header: '行ったライブ・${lives.length}回',
      hasLeading: false,
      children: [
        for (final r in lives)
          MediaListTile(
            title: r.title,
            subtitle: [
              formatJapaneseDateRange(r.date, r.endDate, includeWeekday: true),
              ?r.venue,
            ].join('・'),
            onTap: () => openRecordDetail(context, r),
          ),
      ],
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
  const _Ranking({required this.header, required this.items, this.onTap});

  final String header;
  final List<RankedItem> items;

  /// 行を押したときに項目名を受け取る。null なら押せない。
  final ValueChanged<String>? onTap;

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
            onTap: onTap == null ? null : () => onTap!(item.label),
          ),
      ],
    );
  }
}
