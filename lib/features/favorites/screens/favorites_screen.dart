import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/add_favorite_artist_sheet.dart';
import 'package:recolle/features/favorites/widgets/artist_avatar.dart';
import 'package:recolle/features/music/screens/artist_detail_screen.dart';
import 'package:recolle/features/records/providers/records_provider.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoriteArtistsProvider);
    final records = ref.watch(recordsProvider).asData?.value ?? const [];
    final readOnlyOffline = ref.watch(isOfflineReadOnlyProvider);

    Future<void> confirmRemove(FavoriteArtist artist) async {
      final ok = await showConfirmDialog(
        context,
        title: 'お気に入りから外す',
        message: '「${artist.name}」をお気に入りから外しますか？\n記録は削除されません。',
        okText: '外す',
      );
      if (!ok || !context.mounted) return;
      try {
        await ref.read(favoriteArtistsProvider.notifier).remove(artist.id);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(toUserFriendlyMessage(e))));
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('FAVORITES'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.person_add_alt_1_outlined,
              color: readOnlyOffline ? AppColors.textDisabled : AppColors.gold,
            ),
            tooltip: readOnlyOffline ? 'オフラインでは追加できません' : 'アーティストを追加',
            onPressed: readOnlyOffline
                ? null
                : () => showAddFavoriteArtistSheet(context),
          ),
        ],
      ),
      body: favoritesAsync.when(
        data: (favorites) {
          if (favorites.isEmpty) {
            return _EmptyFavorites(
              onAdd: readOnlyOffline
                  ? null
                  : () => showAddFavoriteArtistSheet(context),
            );
          }
          return RefreshIndicator(
            color: AppColors.gold,
            onRefresh: () => ref.refresh(favoriteArtistsProvider.future),
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.78,
              ),
              itemCount: favorites.length,
              itemBuilder: (context, index) {
                final artist = favorites[index];
                final count = records
                    .where((r) => artistMatches(r.artistOrAuthor, artist.name))
                    .length;
                return _FavoriteArtistCard(
                  artist: artist,
                  recordCount: count,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ArtistDetailScreen(
                        artistName: artist.name,
                        itunesArtistId: artist.itunesArtistId,
                        artworkUrl: artist.artworkUrl,
                        heroTag: 'favorite-artist-${artist.id}',
                      ),
                    ),
                  ),
                  onLongPress: readOnlyOffline
                      ? null
                      : () => confirmRemove(artist),
                );
              },
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.gold),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  toUserFriendlyMessage(error),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => ref.invalidate(favoriteArtistsProvider),
                  child: const Text('再読み込み'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteArtistCard extends StatelessWidget {
  const _FavoriteArtistCard({
    required this.artist,
    required this.recordCount,
    required this.onTap,
    this.onLongPress,
  });

  final FavoriteArtist artist;
  final int recordCount;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Hero(
                  tag: 'favorite-artist-${artist.id}',
                  child: ArtistAvatar(
                    name: artist.name,
                    artworkUrl: artist.artworkUrl,
                    size: constraints.maxWidth,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.displayStyle(
                      fontSize: 20,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$recordCount RECORDS',
                    style: AppFonts.monoStyle(
                      fontSize: 11,
                      color: AppColors.gold.withValues(alpha: 0.85),
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

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_border_rounded,
              size: 64,
              color: AppColors.gold.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'お気に入りのアーティストを登録すると、\n記録の作成や絞り込みがすばやくなります。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.6),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('アーティストを追加'),
            ),
          ],
        ),
      ),
    );
  }
}
