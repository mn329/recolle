import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/hooks/use_debounced_search.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/artist_avatar.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';

/// お気に入りアーティストをワンタップで入力するチップ列。未登録なら何も出さない。
class FavoriteArtistQuickPick extends ConsumerWidget {
  const FavoriteArtistQuickPick({
    super.key,
    required this.currentArtist,
    required this.onPick,
  });

  final String currentArtist;
  final ValueChanged<FavoriteArtist> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites =
        ref.watch(favoriteArtistsProvider).asData?.value ??
        const <FavoriteArtist>[];
    if (favorites.isEmpty) return const SizedBox.shrink();

    final current = normalizeArtistName(currentArtist);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: favorites.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final artist = favorites[index];
            final selected = normalizeArtistName(artist.name) == current;
            return ActionChip(
              avatar: ArtistAvatar(
                name: artist.name,
                artworkUrl: artist.artworkUrl,
                size: 20,
              ),
              label: Text(artist.name),
              onPressed: () => onPick(artist),
              labelStyle: TextStyle(
                color: selected ? Colors.black : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
              backgroundColor: selected ? AppColors.gold : AppColors.surface,
              visualDensity: VisualDensity.compact,
              shape: StadiumBorder(
                side: BorderSide(
                  color: selected
                      ? Colors.transparent
                      : AppColors.textDisabled.withValues(alpha: 0.5),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// iTunes のアーティスト候補。[query] が空なら何も出さない。
class ArtistSuggestions extends HookConsumerWidget {
  const ArtistSuggestions({
    super.key,
    required this.query,
    required this.onPick,
  });

  final String query;
  final ValueChanged<ItunesArtist> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itunes = ref.watch(itunesClientProvider);
    final snapshot = useDebouncedSearch<ItunesArtist>(
      query,
      (q) => itunes.searchArtists(q, limit: 5),
      minLength: 2,
    );
    final normalizedQuery = normalizeArtistName(query);
    final artists = (snapshot.data ?? const <ItunesArtist>[])
        .where((a) => normalizeArtistName(a.name) != normalizedQuery)
        .toList();

    return _SuggestionPanel(
      snapshot: snapshot,
      isEmpty: artists.isEmpty,
      children: [
        for (final artist in artists)
          _SuggestionRow(
            icon: Icons.person_outline,
            title: artist.name,
            subtitle: artist.genre,
            onTap: () => onPick(artist),
          ),
      ],
    );
  }
}

/// セトリ入力中の曲名候補。アーティスト名で絞り込む。
class SongSuggestions extends HookConsumerWidget {
  const SongSuggestions({
    super.key,
    required this.artistName,
    required this.query,
    required this.alreadyAdded,
    required this.onPick,
  });

  final String artistName;
  final String query;

  /// 既にセトリにある曲は候補から外す。
  final Iterable<String> alreadyAdded;
  final ValueChanged<ItunesSong> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itunes = ref.watch(itunesClientProvider);
    final snapshot = useDebouncedSearch<ItunesSong>(
      query,
      (q) => itunes.searchSongs(artistName: artistName, term: q),
    );
    final added = {for (final t in alreadyAdded) normalizeArtistName(t)};
    final songs = (snapshot.data ?? const <ItunesSong>[])
        .where((s) => !added.contains(normalizeArtistName(s.title)))
        .toList();

    return _SuggestionPanel(
      snapshot: snapshot,
      isEmpty: songs.isEmpty,
      children: [
        for (final song in songs)
          _SuggestionRow(
            leading: song.artworkUrl == null
                ? null
                : ArtistAvatar(
                    name: song.title,
                    artworkUrl: song.artworkUrl,
                    size: 32,
                    borderRadius: BorderRadius.circular(4),
                  ),
            icon: Icons.music_note_outlined,
            title: song.title,
            subtitle: song.artistName,
            onTap: () => onPick(song),
          ),
      ],
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.snapshot,
    required this.isEmpty,
    required this.children,
  });

  final AsyncSnapshot<Object?> snapshot;
  final bool isEmpty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final Widget? content;
    if (snapshot.hasError) {
      content = Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          toUserFriendlyMessage(snapshot.error),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    } else if (!isEmpty) {
      content = Column(mainAxisSize: MainAxisSize.min, children: children);
    } else if (snapshot.connectionState == ConnectionState.waiting) {
      content = const LinearProgressIndicator(
        minHeight: 2,
        color: AppColors.gold,
        backgroundColor: Colors.transparent,
      );
    } else {
      content = null;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: content == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.18),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: content,
            ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.leading,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            leading ??
                Icon(
                  icon,
                  size: 20,
                  color: AppColors.gold.withValues(alpha: 0.8),
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.north_west_rounded,
              size: 16,
              color: AppColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}
