import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/components/record_ticket_list.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/artist_avatar.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/record_actions.dart';
import 'package:recolle/features/search/screens/search_screen.dart';

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
    final selectedFavoriteId = useState<String?>(null);

    // 選択中のお気に入りが削除されたら絞り込みを解除する
    final selectedFavorite = favorites
        .where((f) => f.id == selectedFavoriteId.value)
        .firstOrNull;

    void openEditor() => openRecordEditor(
      context,
      initialType: selectedType.value,
      initialArtist: selectedFavorite?.name,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: LargeTitleScrollView(
        title: 'RECOLLE',
        largeTitle: Text(
          'RECOLLE',
          style: AppFonts.displayStyle(
            fontSize: 38,
            color: AppColors.gold,
            letterSpacing: 3,
          ),
        ),
        middle: Text(
          'RECOLLE',
          style: AppFonts.displayStyle(
            fontSize: 22,
            color: AppColors.gold,
            letterSpacing: 2,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NavBarIconButton(
              icon: CupertinoIcons.search,
              semanticLabel: '検索',
              onPressed: () => Navigator.push(
                context,
                CupertinoPageRoute<void>(builder: (_) => const SearchScreen()),
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
          favorites: favorites,
          selectedFavoriteId: selectedFavorite?.id,
          onFavoriteSelected: (id) => selectedFavoriteId.value = id,
        ),
        onRefresh: () => ref.refresh(recordsProvider.future),
        slivers: [
          if (readOnlyOffline)
            const SliverToBoxAdapter(child: _OfflineBanner()),
          recordsAsync.when(
            data: (records) {
              final visible = records.where(
                (r) =>
                    r.type == selectedType.value &&
                    (selectedFavorite == null ||
                        artistMatches(r.artistOrAuthor, selectedFavorite.name)),
              );
              return SliverRecordTicketList(
                records: visible.toList(),
                emptyTitle: selectedFavorite == null
                    ? '${selectedType.value.japaneseLabel}の記録はまだありません'
                    : '${selectedFavorite.name} の記録はまだありません',
                emptyMessage: '行ったライブや観た作品を、チケットと一緒に残しましょう。',
                emptyActionLabel: readOnlyOffline ? null : '記録を追加',
                onEmptyAction: readOnlyOffline ? null : openEditor,
              );
            },
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CupertinoActivityIndicator(radius: 14)),
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
        ],
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
    required this.selectedFavoriteId,
    required this.onFavoriteSelected,
  });

  final RecordType selectedType;
  final ValueChanged<RecordType> onTypeChanged;
  final List<FavoriteArtist> favorites;
  final String? selectedFavoriteId;
  final ValueChanged<String?> onFavoriteSelected;

  static const double _segmentHeight = 48;
  static const double _chipsHeight = 44;

  @override
  Size get preferredSize =>
      Size.fromHeight(_segmentHeight + (favorites.isEmpty ? 0 : _chipsHeight));

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
          SizedBox(
            height: _chipsHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              itemCount: favorites.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return CapsuleChip(
                    label: 'すべて',
                    selected: selectedFavoriteId == null,
                    onTap: () => onFavoriteSelected(null),
                  );
                }
                final artist = favorites[index - 1];
                return CapsuleChip(
                  label: artist.name,
                  selected: selectedFavoriteId == artist.id,
                  avatar: ArtistAvatar(
                    name: artist.name,
                    artworkUrl: artist.artworkUrl,
                    size: 22,
                  ),
                  onTap: () => onFavoriteSelected(
                    selectedFavoriteId == artist.id ? null : artist.id,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(CupertinoIcons.wifi_slash, size: 18, color: AppColors.gold),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'オフラインです。キャッシュがある記録は閲覧のみできます。',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
