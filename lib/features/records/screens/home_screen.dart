import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/components/record_ticket_list.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/core/widgets/content_switcher.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/favorite_artist_chips.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/record_actions.dart';
import 'package:recolle/features/records/record_timeline.dart';
import 'package:recolle/features/records/widgets/next_event_card.dart';
import 'package:recolle/features/search/screens/search_screen.dart';
import 'package:recolle/core/widgets/app_background.dart';

/// ジャンルを切り替えるスワイプとみなす、横方向の速さの下限（論理ピクセル/秒）。
const double _swipeMinVelocity = 300;

class HomeScreen extends HookConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(recordsProvider);
    final readOnlyOffline = ref.watch(isOfflineReadOnlyProvider);
    final favorites =
        ref.watch(favoriteArtistsProvider).asData?.value ??
        const <FavoriteArtist>[];
    final selectedType = useState(RecordType.live);
    final selectedArtistName = useState<String?>(null);
    final upcomingSort = useState(TimelineSort.defaultFor(upcoming: true));
    final pastSort = useState(TimelineSort.defaultFor(upcoming: false));

    // お気に入りはアーティストなので、ライブ以外では出さず絞り込みもしない
    final isLive = selectedType.value == RecordType.live;
    // 選択中のお気に入りが削除されたら絞り込みを解除する
    final selectedFavorite = isLive
        ? favorites.where((f) => f.name == selectedArtistName.value).firstOrNull
        : null;

    void openEditor() => openRecordEditor(
      context,
      initialType: selectedType.value,
      initialArtist: selectedFavorite?.name,
    );

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 左右にスワイプして、ジャンルのタブを切り替える（縦のスクロールや、お気に入りの横スクロールとは競合しない）
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity.abs() < _swipeMinVelocity) return;
            final types = RecordType.values;
            final next =
                types.indexOf(selectedType.value) + (velocity < 0 ? 1 : -1);
            if (next < 0 || next >= types.length) return;
            HapticFeedback.selectionClick();
            selectedType.value = types[next];
          },
          child: LargeTitleScrollView(
            title: 'RECOLLE',
            enTitle: 'RECOLLE',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                NavBarIconButton(
                  icon: CupertinoIcons.search,
                  semanticLabel: '検索',
                  onPressed: () => Navigator.push(
                    context,
                    CupertinoPageRoute<void>(
                      builder: (_) => const SearchScreen(),
                    ),
                  ),
                ),
                NavBarIconButton(
                  icon: CupertinoIcons.plus_circle_fill,
                  semanticLabel: readOnlyOffline ? 'オフラインでは新規作成できません' : '記録を追加',
                  onPressed: readOnlyOffline ? null : openEditor,
                ),
              ],
            ),
            bottom: _HomeFilterBar(
              selectedType: selectedType.value,
              onTypeChanged: (t) => selectedType.value = t,
              favorites: isLive ? favorites : const [],
              selectedArtistName: selectedFavorite?.name,
              onArtistSelected: (name) => selectedArtistName.value = name,
            ),
            onRefresh: () => ref.refresh(recordsProvider.future),
            contentKey: (selectedType.value, selectedFavorite?.name),
            slivers: [
              if (readOnlyOffline)
                const SliverToBoxAdapter(child: _NoticeBanner.offline())
              else if (recordsAsync.hasError && recordsAsync.hasValue)
                SliverToBoxAdapter(
                  child: _NoticeBanner(
                    icon: CupertinoIcons.exclamationmark_triangle,
                    message:
                        '最新の記録を読み込めませんでした。${toUserFriendlyMessage(recordsAsync.error)}',
                    actionLabel: '再読み込み',
                    onAction: () => ref.invalidate(recordsProvider),
                  ),
                ),
              SliverContentSwitcher(
                contentKey: (selectedType.value, selectedFavorite?.name),
                // 読み込みに失敗しても、表示中（または手元のキャッシュ）の一覧は消さない
                sliver: recordsAsync.when(
                  skipError: true,
                  data: (records) {
                    final visible = records.where(
                      (r) =>
                          r.type == selectedType.value &&
                          (selectedFavorite == null ||
                              r.features(selectedFavorite.name)),
                    );
                    final (:upcoming, :past) = splitByDate(
                      visible,
                      DateTime.now(),
                    );
                    if (upcoming.isEmpty && past.isEmpty) {
                      return SliverRecordTicketList(
                        records: const [],
                        emptyTitle: selectedFavorite == null
                            ? '${selectedType.value.japaneseLabel}の記録はまだありません'
                            : '${selectedFavorite.name} の記録はまだありません',
                        emptyMessage: '行ったライブや観た作品を、チケットと一緒に残しましょう。',
                        emptyActionLabel: readOnlyOffline ? null : '記録を追加',
                        onEmptyAction: readOnlyOffline ? null : openEditor,
                      );
                    }
                    return SliverMainAxisGroup(
                      slivers: [
                        if (upcoming.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: NextEventCard(record: upcoming.first),
                          ),
                          ..._timelineSection(
                            title: 'これから',
                            records: upcoming,
                            upcoming: true,
                            type: selectedType.value,
                            sort: upcomingSort,
                          ),
                        ],
                        if (past.isNotEmpty)
                          ..._timelineSection(
                            title: 'これまで',
                            records: past,
                            upcoming: false,
                            type: selectedType.value,
                            sort: pastSort,
                          ),
                      ],
                    );
                  },
                  loading: () => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CupertinoActivityIndicator(radius: 14),
                    ),
                  ),
                  error: (error, stack) => SliverFillRemaining(
                    hasScrollBody: false,
                    child: IosEmptyState(
                      icon: CupertinoIcons.exclamationmark_triangle,
                      message: toUserFriendlyMessage(error),
                      actionLabel: '再読み込み',
                      onAction: () => ref.invalidate(recordsProvider),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「これから」「これまで」の見出しと一覧。ライブ形態順なら形態ごとに小見出しを付ける。
List<Widget> _timelineSection({
  required String title,
  required List<Record> records,
  required bool upcoming,
  required RecordType type,
  required ValueNotifier<TimelineSort> sort,
}) {
  final options = TimelineSort.optionsFor(type);
  // ライブで選んだ形態順のまま映画などに切り替えたときは、既定の順に戻す
  final effective = options.contains(sort.value)
      ? sort.value
      : TimelineSort.defaultFor(upcoming: upcoming);
  final sorted = sortTimeline(records, effective, upcoming: upcoming);
  return [
    _SectionHeader(
      '$title・${records.length}件',
      trailing: _SortButton(
        sectionTitle: title,
        current: effective,
        options: options,
        upcoming: upcoming,
        onChanged: (value) => sort.value = value,
      ),
    ),
    if (effective == TimelineSort.eventFormat)
      for (final (:format, records: group) in groupByEventFormat(sorted)) ...[
        _SubsectionHeader('${format.label}・${group.length}件'),
        SliverRecordTicketList(records: group),
      ]
    else
      SliverRecordTicketList(records: sorted),
  ];
}

class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.sectionTitle,
    required this.current,
    required this.options,
    required this.upcoming,
    required this.onChanged,
  });

  final String sectionTitle;
  final TimelineSort current;
  final List<TimelineSort> options;
  final bool upcoming;
  final ValueChanged<TimelineSort> onChanged;

  Future<void> _choose(BuildContext context) async {
    final chosen = await showActionSheet<TimelineSort>(
      context,
      title: '「$sectionTitle」の並び順',
      actions: [
        for (final option in options)
          SheetAction(
            label: option == current
                ? '${option.labelFor(upcoming: upcoming)}（選択中）'
                : option.labelFor(upcoming: upcoming),
            value: option,
          ),
      ],
    );
    if (chosen != null) onChanged(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final label = current.labelFor(upcoming: upcoming);
    return Semantics(
      button: true,
      label: '「$sectionTitle」の並び順：$label',
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 32),
        onPressed: () => _choose(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            const Icon(CupertinoIcons.arrow_up_arrow_down, size: 13),
          ],
        ),
      ),
    );
  }
}

/// ナビゲーションバーの下に固定する、種別の切り替えとお気に入りの絞り込み。
class _HomeFilterBar extends StatelessWidget implements PreferredSizeWidget {
  const _HomeFilterBar({
    required this.selectedType,
    required this.onTypeChanged,
    required this.favorites,
    required this.selectedArtistName,
    required this.onArtistSelected,
  });

  final RecordType selectedType;
  final ValueChanged<RecordType> onTypeChanged;
  final List<FavoriteArtist> favorites;
  final String? selectedArtistName;
  final ValueChanged<String?> onArtistSelected;

  static const double _segmentHeight = 48;

  @override
  Size get preferredSize => Size.fromHeight(
    _segmentHeight + (favorites.isEmpty ? 0 : FavoriteArtistChips.height),
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
            child: IosSegmentedControl<RecordType>(
              value: selectedType,
              segments: {for (final t in RecordType.values) t: t.japaneseLabel},
              onChanged: onTypeChanged,
            ),
          ),
        ),
        if (favorites.isNotEmpty)
          FavoriteArtistChips(
            favorites: favorites,
            selectedName: selectedArtistName,
            onSelected: onArtistSelected,
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(28, trailing == null ? 20 : 12, 20, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: sectionHeaderTextStyle(context)),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _SubsectionHeader extends StatelessWidget {
  const _SubsectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 一覧の上に出す、オフライン・読み込み失敗のお知らせ。
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  const _NoticeBanner.offline()
    : this(
        icon: CupertinoIcons.wifi_slash,
        message: 'オフラインです。キャッシュがある記録は閲覧のみできます。',
      );

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.colors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          if (actionLabel case final label?)
            CupertinoButton(
              padding: const EdgeInsets.only(left: 8),
              minimumSize: const Size(44, 44),
              onPressed: onAction,
              child: Text(label, style: const TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
  }
}
