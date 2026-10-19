import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/utils/japanese_date_format.dart';
import 'package:recolle/core/utils/yen_format.dart';
import 'package:recolle/core/widgets/content_switcher.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/favorite_artist_chips.dart';
import 'package:recolle/features/music/screens/song_detail_screen.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/record_actions.dart';
import 'package:recolle/features/records/record_stats.dart';
import 'package:recolle/features/records/record_timeline.dart';
import 'package:recolle/features/records/screens/live_list_screen.dart';
import 'package:recolle/features/records/screens/venue_detail_screen.dart';
import 'package:recolle/features/records/widgets/ranking_section.dart';
import 'package:recolle/features/records/widgets/record_calendar_view.dart';
import 'package:recolle/core/widgets/app_background.dart';

enum InsightsView {
  stats('集計'),
  calendar('カレンダー');

  const InsightsView(this.label);

  final String label;
}

/// 振り返りで絞り込むジャンル。[type] が null なら全ジャンル（「すべて」）。
enum InsightsGenre {
  all(null),
  live(RecordType.live),
  movie(RecordType.movie),
  book(RecordType.book),
  other(RecordType.other);

  const InsightsGenre(this.type);

  final RecordType? type;

  String get label => type?.japaneseLabel ?? 'すべて';

  /// お気に入りのアーティストで絞れるか。アーティストはライブの出演者なので、ライブだけ。
  bool get supportsArtist => this == live;
}

/// 「振り返り」タブ。年ごとの参戦回数・チケット代・ランキング（最初に出す）とカレンダーを切り替える。
///
/// ジャンル（すべて・ライブ・映画・本・その他）で、カレンダーも集計もそのジャンルの記録だけになる。
/// ホームと同じお気に入りアーティストのチップ（または集計のランキング）でアーティストを選ぶと、
/// カレンダーも集計もそのアーティストの記録だけになる。
class InsightsScreen extends HookConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(recordsProvider);
    final view = useState(InsightsView.stats);
    final genre = useState(InsightsGenre.all);
    final selectedYear = useState<int?>(DateTime.now().year);
    final selectedArtistState = useState<String?>(null);
    // アーティストで絞れないジャンルでは、選んでいても無視する（ホームのお気に入りと同じ）
    final selectedArtist = genre.value.supportsArtist
        ? selectedArtistState.value
        : null;
    final allFavorites =
        ref.watch(favoriteArtistsProvider).asData?.value ??
        const <FavoriteArtist>[];
    final favorites = genre.value.supportsArtist
        ? allFavorites
        : const <FavoriteArtist>[];

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LargeTitleScrollView(
          title: '振り返り',
          enTitle: 'LOOK BACK',
          bottom: _InsightsFilterBar(
            view: view.value,
            onViewChanged: (v) => view.value = v,
            genre: genre.value,
            onGenreChanged: (g) => genre.value = g,
            favorites: favorites,
            selectedArtist: selectedArtist,
            onArtistSelected: (a) => selectedArtistState.value = a,
          ),
          onRefresh: () => ref.refresh(recordsProvider.future),
          contentKey: (view.value, genre.value, selectedArtist),
          slivers: [
            // 読み込みに失敗しても、表示中（または手元のキャッシュ）の内容は消さない
            recordsAsync.when(
              // 再読み込み中も、直前の一覧を残す（読み込み中の表示に切り替えない）
              skipLoadingOnReload: true,
              skipError: true,
              data: (records) {
                final artist = selectedArtist;
                final filtered = filterByArtist(
                  filterByType(records, genre.value.type),
                  artist,
                );
                final isCalendar = view.value == InsightsView.calendar;
                return SliverToBoxAdapter(
                  child: ContentSwitcher(
                    // カレンダーは選んだ月を保つため、ジャンルやアーティストを変えても作り直さない
                    contentKey: isCalendar
                        ? view.value
                        : (view.value, genre.value, artist),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isCalendar)
                          RecordCalendarView(records: filtered)
                        else if (genre.value == InsightsGenre.all)
                          ..._overviewChildren(
                            context,
                            filtered,
                            selectedYear,
                            onGenreSelected: (g) => genre.value = g,
                          )
                        else if (genre.value.type case final type?
                            when type != RecordType.live)
                          ..._genreChildren(
                            context,
                            filtered,
                            selectedYear,
                            type: type,
                          )
                        else
                          ..._statsChildren(
                            context,
                            filtered,
                            selectedYear,
                            artist: artist,
                            onArtistSelected: (a) =>
                                selectedArtistState.value = a,
                          ),
                        SizedBox(
                          height: 24 + MediaQuery.paddingOf(context).bottom,
                        ),
                      ],
                    ),
                  ),
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
    final years = yearsWithRecords(records);
    // 選択中の年に記録がなければ（年が明けた直後など）全期間にする
    final year = years.contains(selectedYear.value) ? selectedYear.value : null;
    final stats = computeStats(
      records,
      now: now,
      year: year,
      artist: artist,
      rankingLimit: artist == null ? 5 : 10,
    );
    final nextLive = artist == null
        ? null
        : splitByDate(
            records,
            now,
          ).upcoming.where((r) => r.type == RecordType.live).firstOrNull;
    void openLives({int? month}) => Navigator.push(
      context,
      CupertinoPageRoute<void>(
        builder: (_) =>
            LiveListScreen(year: year, month: month, artist: artist),
      ),
    );
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
                ? 'ライブを記録すると、ここに集計が表示されます。'
                : '$artistのライブの記録はまだありません。',
          ),
        )
      else ...[
        _Summary(
          stats: stats,
          showsArtistCount: artist == null,
          onLivesTap: stats.liveCount == 0 ? null : openLives,
        ),
        // 初めて・最後に行った日は、選んだ年ではなく全期間で数える
        if (artist != null)
          _ArtistMilestones(
            stats: computeStats(records, now: now, artist: artist),
            nextLive: nextLive,
          ),
        if (artist == null)
          _MonthlyChart(
            counts: stats.liveCountsByMonth,
            onMonthTap: (m) => openLives(month: m),
          ),
        if (artist == null)
          RankingSection(
            header: 'よく行ったアーティスト',
            rows: [
              for (final a in stats.topArtists)
                (
                  title: a.label,
                  subtitle: null,
                  count: a.count,
                  onTap: () => onArtistSelected(a.label),
                ),
            ],
          ),
        RankingSection(
          header: 'よく聴いた曲',
          rows: [
            for (final s in stats.topSongs)
              (
                title: s.title,
                // アーティストで絞っているときは全部同じなので出さない
                subtitle: artist == null ? s.artist : null,
                count: s.count,
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute<void>(
                    builder: (_) =>
                        SongDetailScreen(artistName: s.artist, title: s.title),
                  ),
                ),
              ),
          ],
        ),
        RankingSection(
          header: 'よく行った会場',
          rows: [
            for (final v in stats.topVenues)
              (
                title: v.label,
                subtitle: null,
                count: v.count,
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute<void>(
                    builder: (_) => VenueDetailScreen(
                      venue: v.label,
                      year: year,
                      artist: artist,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (artist != null)
          _History(header: 'ライブ・${stats.lives.length}回', records: stats.lives),
      ],
    ];
  }

  /// 「すべて」の集計。ジャンルをまたいだ件数・金額・月別と、ジャンルごとの内訳だけを出す。
  /// アーティスト・曲・会場のランキングはジャンルごとに意味が違うので、各ジャンルで見る。
  List<Widget> _overviewChildren(
    BuildContext context,
    List<Record> records,
    ValueNotifier<int?> selectedYear, {
    required ValueChanged<InsightsGenre> onGenreSelected,
  }) {
    final years = yearsWithRecords(records);
    // 選択中の年に記録がなければ（年が明けた直後など）全期間にする
    final year = years.contains(selectedYear.value) ? selectedYear.value : null;
    final stats = computeOverviewStats(records, year: year);
    return [
      if (years.length > 1)
        _ChipRow<int>(
          allLabel: 'すべての年',
          items: [for (final y in years) ('$y年', y)],
          selected: year,
          onSelected: (y) => selectedYear.value = y,
        ),
      if (stats.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: IosEmptyState(
            icon: CupertinoIcons.chart_bar,
            message: '記録を追加すると、ここに集計が表示されます。',
          ),
        )
      else ...[
        _OverviewSummary(stats: stats),
        _GenreBreakdown(
          stats: stats,
          onGenreSelected: (type) => onGenreSelected(
            InsightsGenre.values.firstWhere((g) => g.type == type),
          ),
        ),
        _MonthlyChart(header: '月別の記録', unit: '件', counts: stats.countsByMonth),
      ],
    ];
  }

  /// ライブ以外のジャンル（映画・本・その他）の集計。出演者やセトリがないので、
  /// 件数・金額・月別・会場・一覧だけを出す。
  List<Widget> _genreChildren(
    BuildContext context,
    List<Record> records,
    ValueNotifier<int?> selectedYear, {
    required RecordType type,
  }) {
    final years = yearsWithRecords(records);
    // 選択中の年に記録がなければ（年が明けた直後など）全期間にする
    final year = years.contains(selectedYear.value) ? selectedYear.value : null;
    final stats = computeGenreStats(records, type: type, year: year);
    return [
      if (years.length > 1)
        _ChipRow<int>(
          allLabel: 'すべての年',
          items: [for (final y in years) ('$y年', y)],
          selected: year,
          onSelected: (y) => selectedYear.value = y,
        ),
      if (stats.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: IosEmptyState(
            icon: CupertinoIcons.chart_bar,
            message: '${type.japaneseLabel}を記録すると、ここに集計が表示されます。',
          ),
        )
      else ...[
        _GenreSummary(stats: stats),
        _MonthlyChart(
          header: '月別の${type.japaneseLabel}',
          unit: type.countUnit,
          counts: stats.countsByMonth,
        ),
        if (type.venueLabel case final venueLabel?)
          RankingSection(
            header: 'よく行った$venueLabel',
            rows: [
              for (final v in stats.topVenues)
                (title: v.label, subtitle: null, count: v.count, onTap: null),
            ],
          ),
        _History(
          header: '${type.japaneseLabel}の記録・${stats.count}${type.countUnit}',
          records: stats.records,
        ),
      ],
    ];
  }
}

/// ナビゲーションバーの下に固定する、表示とジャンルの切り替え、アーティストの絞り込み（ホームと同じチップ）。
class _InsightsFilterBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _InsightsFilterBar({
    required this.view,
    required this.onViewChanged,
    required this.genre,
    required this.onGenreChanged,
    required this.favorites,
    required this.selectedArtist,
    required this.onArtistSelected,
  });

  final InsightsView view;
  final ValueChanged<InsightsView> onViewChanged;
  final InsightsGenre genre;
  final ValueChanged<InsightsGenre> onGenreChanged;
  final List<FavoriteArtist> favorites;
  final String? selectedArtist;
  final ValueChanged<String?> onArtistSelected;

  static const double _segmentHeight = 48;

  bool get _showsChips =>
      FavoriteArtistChips.isVisible(favorites, selectedArtist);

  @override
  Size get preferredSize => Size.fromHeight(
    _segmentHeight * 2 + (_showsChips ? FavoriteArtistChips.height : 0),
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
        SizedBox(
          height: _segmentHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: IosSegmentedControl<InsightsGenre>(
              value: genre,
              segments: {for (final g in InsightsGenre.values) g: g.label},
              onChanged: onGenreChanged,
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

/// 振り返りの記録の一覧（新しい順）。アーティストを選んだときのライブや、ライブ以外のジャンルで出す。
class _History extends StatelessWidget {
  const _History({required this.header, required this.records});

  final String header;
  final List<Record> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();
    return InsetGroupedSection(
      header: header,
      hasLeading: false,
      children: [
        for (final r in records)
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
  const _Summary({
    required this.stats,
    required this.showsArtistCount,
    this.onLivesTap,
  });

  final RecordStats stats;
  final bool showsArtistCount;
  final VoidCallback? onLivesTap;

  @override
  Widget build(BuildContext context) {
    final average = stats.averageTicketPrice;
    final byFormat = stats.liveCountsByFormat;
    // ワンマンだけなら内訳は出さない
    final formatBreakdown = byFormat[EventFormat.oneman] == stats.liveCount
        ? null
        : [
            for (final f in EventFormat.values)
              if (byFormat[f]! > 0) '${f.label} ${byFormat[f]}',
          ].join('・');
    final others = [
      if (showsArtistCount && stats.artistCount > 0)
        '観たアーティスト ${stats.artistCount}組',
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
                  caption: formatBreakdown,
                  onTap: onLivesTap,
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

/// 「すべて」の、記録の件数と金額の合計。
class _OverviewSummary extends StatelessWidget {
  const _OverviewSummary({required this.stats});

  final OverviewStats stats;

  @override
  Widget build(BuildContext context) {
    final average = stats.averagePrice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(label: '記録', value: '${stats.count}', unit: '件'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatTile(
              label: '金額の合計',
              value: formatYen(stats.totalPrice),
              caption: average == null
                  ? 'チケット代・価格を入力すると集計されます'
                  : '平均 ${formatYen(average)}',
            ),
          ),
        ],
      ),
    );
  }
}

/// 「すべて」の、ジャンルごとの件数。押すとそのジャンルの集計へ移る。
class _GenreBreakdown extends StatelessWidget {
  const _GenreBreakdown({required this.stats, required this.onGenreSelected});

  final OverviewStats stats;
  final ValueChanged<RecordType> onGenreSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InsetGroupedSection(
      header: 'ジャンル別',
      footer: 'ジャンルを押すと、そのジャンルの集計を見られます',
      hasLeading: false,
      children: [
        for (final g in stats.byType)
          if (g.count > 0)
            GroupedRow(
              title: g.type.japaneseLabel,
              subtitle: g.totalPrice > 0 ? formatYen(g.totalPrice) : null,
              additionalInfo: Text(
                '${g.count}${g.type.countUnit}',
                style: TextStyle(fontSize: 15, color: colors.textSecondary),
              ),
              onTap: () => onGenreSelected(g.type),
            ),
      ],
    );
  }
}

/// ライブ以外のジャンルの、件数と金額の合計。
class _GenreSummary extends StatelessWidget {
  const _GenreSummary({required this.stats});

  final GenreStats stats;

  @override
  Widget build(BuildContext context) {
    final type = stats.type;
    final average = stats.averagePrice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              label: type.japaneseLabel,
              value: '${stats.count}',
              unit: type.countUnit,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatTile(
              label: '${type.priceLabel}の合計',
              value: formatYen(stats.totalPrice),
              caption: average == null
                  ? '${type.priceLabel}を入力すると集計されます'
                  : '平均 ${formatYen(average)}',
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
    this.onTap,
  });

  final String label;
  final String value;
  final String? unit;
  final String? caption;

  /// null なら押せない。押せるときは見出しの横に「›」を出す。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tile = Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ),
              if (onTap != null)
                Icon(
                  CupertinoIcons.chevron_forward,
                  size: 13,
                  color: colors.textSecondary,
                ),
            ],
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
    if (onTap == null) return tile;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: tile,
      ),
    );
  }
}

/// 月別の件数の棒グラフ。[onMonthTap] があれば、記録のある月を押してその月の一覧を開ける。
class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({
    required this.counts,
    this.header = '月別のライブ',
    this.unit = '回',
    this.onMonthTap,
  });

  final List<int> counts;
  final String header;

  /// 件数の単位（「3月 2回」の「回」）。
  final String unit;

  /// 押された月（1〜12）。null なら棒は押せない。
  final ValueChanged<int>? onMonthTap;

  static const double _barAreaHeight = 96;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final max = counts.fold(0, (a, b) => a > b ? a : b);
    final onMonthTap = this.onMonthTap;
    return InsetGroupedSection(
      header: header,
      footer: onMonthTap != null && counts.any((c) => c > 0)
          ? '棒を押すと、その月のライブを一覧できます'
          : null,
      hasLeading: false,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, c) in counts.indexed)
                Expanded(
                  child: Semantics(
                    button: c > 0 && onMonthTap != null,
                    label: '${i + 1}月 $c$unit',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: c == 0 || onMonthTap == null
                          ? null
                          : () => onMonthTap(i + 1),
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
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
