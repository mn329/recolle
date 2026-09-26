import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/music/providers/music_providers.dart';

/// アーティスト名の横に置く、お気に入り登録・解除の星ボタン。
class FavoriteArtistToggleButton extends HookConsumerWidget {
  const FavoriteArtistToggleButton({super.key, required this.artistName});

  final String artistName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteArtistsProvider).asData?.value;
    final readOnlyOffline = ref.watch(isOfflineReadOnlyProvider);
    final isBusy = useState(false);
    if (favorites == null || artistName.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final target = normalizeArtistName(artistName);
    final existing = favorites
        .where((f) => normalizeArtistName(f.name) == target)
        .firstOrNull;

    Future<void> toggle() async {
      isBusy.value = true;
      final messenger = ScaffoldMessenger.of(context);
      final notifier = ref.read(favoriteArtistsProvider.notifier);
      try {
        if (existing != null) {
          await notifier.remove(existing.id);
          messenger.showSnackBar(
            SnackBar(content: Text('「${existing.name}」をお気に入りから外しました')),
          );
        } else {
          String? artworkUrl;
          try {
            artworkUrl = await ref
                .read(itunesClientProvider)
                .findArtistArtwork(artistName);
          } catch (e) {
            // アートワークは任意項目なので、取得失敗でも登録は続ける
            debugPrint('Artwork lookup failed for $artistName: $e');
          }
          await notifier.add(name: artistName, artworkUrl: artworkUrl);
          messenger.showSnackBar(
            SnackBar(content: Text('「${artistName.trim()}」をお気に入りに追加しました')),
          );
        }
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(toUserFriendlyMessage(e))),
        );
      } finally {
        if (context.mounted) isBusy.value = false;
      }
    }

    return IconButton(
      tooltip: existing != null ? 'お気に入りから外す' : 'お気に入りに追加',
      onPressed: readOnlyOffline || isBusy.value ? null : toggle,
      icon: Icon(
        existing != null ? Icons.star_rounded : Icons.star_border_rounded,
        color: existing != null ? AppColors.gold : AppColors.textSecondary,
      ),
    );
  }
}
