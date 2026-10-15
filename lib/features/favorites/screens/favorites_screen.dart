import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/app_toast.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/pick_artist_image.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/add_favorite_artist_sheet.dart';
import 'package:recolle/features/favorites/widgets/artist_avatar.dart';
import 'package:recolle/features/music/screens/artist_detail_screen.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/core/widgets/app_background.dart';

/// 進行中の表示を見分けるためのキー（テスト用）。
@visibleForTesting
const blockingProgressKey = ValueKey('favorites-blocking-progress');

enum _ArtistAction { changeImage, resetImage, remove }

/// [task] が終わるまで、操作を受け付けない進行中の表示を出す。失敗した例外は呼び出し元に渡す。
Future<T> _withBlockingProgress<T>(
  BuildContext context,
  Future<T> Function() task,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          key: blockingProgressKey,
          child: CupertinoActivityIndicator(radius: 14),
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    navigator.pop();
  }
}

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoriteArtistsProvider);
    final records = ref.watch(recordsProvider).asData?.value ?? const [];
    final readOnlyOffline = ref.watch(isOfflineReadOnlyProvider);

    void openAddSheet() => showAddFavoriteArtistSheet(context);

    Future<void> removeFavorite(FavoriteArtist artist) async {
      try {
        await ref.read(favoriteArtistsProvider.notifier).remove(artist.id);
        AppToast.show(
          '「${artist.name}」をお気に入りから外しました',
          icon: CupertinoIcons.star_slash,
        );
      } catch (e) {
        AppToast.error(toUserFriendlyMessage(e));
      }
    }

    Future<void> changeImage(FavoriteArtist artist) async {
      final notifier = ref.read(favoriteArtistsProvider.notifier);
      final pickImage = ref.read(artistImagePickerProvider);
      try {
        final file = await pickImage(context);
        if (file == null || !context.mounted) return;
        await _withBlockingProgress(
          context,
          () => notifier.changeImage(artist.id, file),
        );
        AppToast.show('画像を変更しました', icon: CupertinoIcons.checkmark_circle_fill);
      } catch (e) {
        AppToast.error(toUserFriendlyMessage(e));
      }
    }

    Future<void> resetImage(FavoriteArtist artist) async {
      final notifier = ref.read(favoriteArtistsProvider.notifier);
      try {
        await _withBlockingProgress(
          context,
          () => notifier.resetImage(artist.id),
        );
        AppToast.show('元の写真に戻しました', icon: CupertinoIcons.checkmark_circle_fill);
      } catch (e) {
        AppToast.error(toUserFriendlyMessage(e));
      }
    }

    Future<void> showArtistActions(FavoriteArtist artist) async {
      HapticFeedback.mediumImpact();
      final action = await showActionSheet<_ArtistAction>(
        context,
        title: artist.name,
        message: 'お気に入りから外しても、記録は削除されません。',
        actions: [
          const SheetAction(label: '画像を変更', value: _ArtistAction.changeImage),
          if (artist.customImageUrl != null)
            const SheetAction(
              label: '元の写真に戻す',
              value: _ArtistAction.resetImage,
            ),
          const SheetAction(
            label: 'お気に入りから外す',
            value: _ArtistAction.remove,
            isDestructive: true,
          ),
        ],
      );
      if (action == null) return;
      switch (action) {
        case _ArtistAction.changeImage:
          await changeImage(artist);
        case _ArtistAction.resetImage:
          await resetImage(artist);
        case _ArtistAction.remove:
          await removeFavorite(artist);
      }
    }

    void openArtist(FavoriteArtist artist) {
      Navigator.push(
        context,
        CupertinoPageRoute<void>(
          builder: (_) => ArtistDetailScreen(
            artistName: artist.name,
            itunesArtistId: artist.itunesArtistId,
            artworkUrl: artist.displayArtworkUrl,
            heroTag: 'favorite-artist-${artist.id}',
          ),
        ),
      );
    }

    final List<Widget> content = favoritesAsync.when(
      data: (favorites) {
        if (favorites.isEmpty) {
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: IosEmptyState(
                icon: CupertinoIcons.star,
                title: 'お気に入りはまだありません',
                message: 'アーティストを登録すると、記録の作成や絞り込みがすばやくなります。',
                actionLabel: readOnlyOffline ? null : 'アーティストを追加',
                onAction: readOnlyOffline ? null : openAddSheet,
              ),
            ),
          ];
        }
        return [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverGrid.builder(
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
                    .where((r) => r.features(artist.name))
                    .length;
                return _FavoriteArtistCard(
                  artist: artist,
                  recordCount: count,
                  onTap: () => openArtist(artist),
                  onLongPress: readOnlyOffline
                      ? null
                      : () => showArtistActions(artist),
                );
              },
            ),
          ),
          if (!readOnlyOffline)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Text(
                  '長押しで画像の変更・お気に入りから外せます',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ),
        ];
      },
      loading: () => const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CupertinoActivityIndicator(radius: 14)),
        ),
      ],
      error: (error, _) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: IosEmptyState(
            icon: CupertinoIcons.exclamationmark_triangle,
            message: toUserFriendlyMessage(error),
            actionLabel: '再読み込み',
            onAction: () => ref.invalidate(favoriteArtistsProvider),
          ),
        ),
      ],
    );

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LargeTitleScrollView(
          title: 'お気に入り',
          enTitle: 'FAVORITES',
          trailing: NavBarIconButton(
            icon: CupertinoIcons.person_badge_plus,
            semanticLabel: readOnlyOffline ? 'オフラインでは追加できません' : 'アーティストを追加',
            onPressed: readOnlyOffline ? null : openAddSheet,
          ),
          onRefresh: () => ref.refresh(favoriteArtistsProvider.future),
          slivers: content,
        ),
      ),
    );
  }
}

class _FavoriteArtistCard extends StatefulWidget {
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
  State<_FavoriteArtistCard> createState() => _FavoriteArtistCardState();
}

class _FavoriteArtistCardState extends State<_FavoriteArtistCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist;
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => ArtistArtworkHero(
                    tag: 'favorite-artist-${artist.id}',
                    name: artist.name,
                    artworkUrl: artist.displayArtworkUrl,
                    size: constraints.maxWidth,
                    // カードの上辺の角丸と揃える
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${widget.recordCount}件の記録',
                      style: AppFonts.monoStyle(
                        fontSize: 11,
                        color: context.colors.accent.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
