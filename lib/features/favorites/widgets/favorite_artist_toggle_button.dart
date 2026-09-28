import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/app_toast.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/music/providers/music_providers.dart';

/// アーティスト名の横に置く、お気に入り登録・解除の星ボタン。
class FavoriteArtistToggleButton extends HookConsumerWidget {
  const FavoriteArtistToggleButton({
    super.key,
    required this.artistName,
    this.itunesArtistId,
  });

  final String artistName;
  final int? itunesArtistId;

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
      HapticFeedback.lightImpact();
      final notifier = ref.read(favoriteArtistsProvider.notifier);
      try {
        if (existing != null) {
          await notifier.remove(existing.id);
          AppToast.show(
            '「${existing.name}」をお気に入りから外しました',
            icon: CupertinoIcons.star_slash,
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
          await notifier.add(
            name: artistName,
            itunesArtistId: itunesArtistId,
            artworkUrl: artworkUrl,
          );
          AppToast.show(
            '「${artistName.trim()}」をお気に入りに追加しました',
            icon: CupertinoIcons.star_fill,
          );
        }
      } catch (e) {
        AppToast.error(toUserFriendlyMessage(e));
      } finally {
        if (context.mounted) isBusy.value = false;
      }
    }

    final enabled = !readOnlyOffline && !isBusy.value;
    return Semantics(
      button: true,
      label: existing != null ? 'お気に入りから外す' : 'お気に入りに追加',
      child: CupertinoButton(
        padding: const EdgeInsets.all(8),
        minimumSize: const Size(44, 44),
        onPressed: enabled ? toggle : null,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Icon(
            existing != null ? CupertinoIcons.star_fill : CupertinoIcons.star,
            key: ValueKey(existing != null),
            size: 24,
            color: existing != null
                ? context.colors.accent
                : enabled
                ? context.colors.textSecondary
                : context.colors.textDisabled,
          ),
        ),
      ),
    );
  }
}
