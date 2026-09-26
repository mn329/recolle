import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/components/record_ticket_list.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/artist_avatar.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/screens/create_record_screen.dart';

class HomeScreen extends HookConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(recordsProvider);
    final readOnlyOffline = ref.watch(isOfflineReadOnlyProvider);
    final favorites =
        ref.watch(favoriteArtistsProvider).asData?.value ??
        const <FavoriteArtist>[];
    final selectedFavoriteId = useState<String?>(null);

    // 選択中のお気に入りが削除されたら絞り込みを解除する
    final selectedFavorite = favorites
        .where((f) => f.id == selectedFavoriteId.value)
        .firstOrNull;

    return DefaultTabController(
      length: RecordType.values.length,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            'RECOLLE',
            style: AppFonts.displayStyle(
              fontSize: 30,
              color: AppColors.gold,
              letterSpacing: 3,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                Icons.add,
                color: readOnlyOffline
                    ? AppColors.textDisabled
                    : AppColors.gold,
              ),
              tooltip: readOnlyOffline ? 'オフラインでは新規作成できません' : '記録を追加',
              onPressed: readOnlyOffline
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CreateRecordScreen(
                            initialArtist: selectedFavorite?.name,
                          ),
                          fullscreenDialog: true,
                        ),
                      );
                    },
            ),
          ],
          bottom: TabBar(
            isScrollable: false,
            indicatorColor: AppColors.gold,
            labelColor: AppColors.gold,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: RecordType.values
                .map((t) => Tab(text: t.japaneseLabel))
                .toList(),
          ),
        ),
        body: recordsAsync.when(
          data: (records) {
            final visible = selectedFavorite == null
                ? records
                : records
                      .where(
                        (r) => artistMatches(
                          r.artistOrAuthor,
                          selectedFavorite.name,
                        ),
                      )
                      .toList();
            final emptyMessage = selectedFavorite == null
                ? '記録がありません'
                : '${selectedFavorite.name} の記録はまだありません';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (readOnlyOffline) const _OfflineBanner(),
                if (favorites.isNotEmpty)
                  _FavoriteFilterBar(
                    favorites: favorites,
                    selectedId: selectedFavorite?.id,
                    onSelected: (id) => selectedFavoriteId.value = id,
                  ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final type in RecordType.values)
                        RecordTicketList(
                          records: visible
                              .where((r) => r.type == type)
                              .toList(),
                          emptyMessage: emptyMessage,
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.gold),
          ),
          error: (error, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                toUserFriendlyMessage(error),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.surfaceLight,
      child: const Row(
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
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

/// お気に入りアーティストで記録を絞り込む横スクロールのチップ列。
class _FavoriteFilterBar extends StatelessWidget {
  const _FavoriteFilterBar({
    required this.favorites,
    required this.selectedId,
    required this.onSelected,
  });

  final List<FavoriteArtist> favorites;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        children: [
          _FilterChip(
            label: 'すべて',
            selected: selectedId == null,
            onTap: () => onSelected(null),
          ),
          for (final artist in favorites)
            _FilterChip(
              label: artist.name,
              selected: selectedId == artist.id,
              avatar: ArtistAvatar(
                name: artist.name,
                artworkUrl: artist.artworkUrl,
                size: 22,
              ),
              onTap: () =>
                  onSelected(selectedId == artist.id ? null : artist.id),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.avatar,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: avatar,
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        labelStyle: TextStyle(
          color: selected ? Colors.black : AppColors.textSecondary,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        ),
        selectedColor: AppColors.gold,
        backgroundColor: AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? Colors.transparent : AppColors.textDisabled,
          ),
        ),
      ),
    );
  }
}
