import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/components/record_ticket_card.dart';
import 'package:recolle/components/record_ticket_list.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/section_title.dart';
import 'package:recolle/features/favorites/widgets/artist_avatar.dart';
import 'package:recolle/features/favorites/widgets/favorite_artist_toggle_button.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:recolle/features/music/screens/song_detail_screen.dart';
import 'package:recolle/features/music/widgets/preview_play_button.dart';
import 'package:recolle/features/music/widgets/streaming_links.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/screens/create_record_screen.dart';

/// アーティスト詳細: ストリーミングへのリンク、人気曲、自分の記録。
class ArtistDetailScreen extends HookConsumerWidget {
  const ArtistDetailScreen({
    super.key,
    required this.artistName,
    this.itunesArtistId,
    this.artworkUrl,
    this.heroTag,
  });

  final String artistName;
  final int? itunesArtistId;
  final String? artworkUrl;

  /// 一覧のアートワークからの Hero 遷移用。
  final String? heroTag;

  static const _collapsedSongCount = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = (ref.watch(recordsProvider).asData?.value ?? const [])
        .where((r) => artistMatches(r.artistOrAuthor, artistName))
        .toList();
    final readOnlyOffline = ref.watch(isOfflineReadOnlyProvider);
    final artistAsync = ref.watch(
      itunesArtistProvider((name: artistName, itunesArtistId: itunesArtistId)),
    );
    final artist = artistAsync.asData?.value;
    final fallbackArtwork = artworkUrl == null
        ? ref.watch(artistArtworkProvider(artistName)).asData?.value
        : null;
    final showAllSongs = useState(false);

    const avatarSize = 104.0;
    const avatarRadius = BorderRadius.all(Radius.circular(14));
    final resolvedArtwork = artworkUrl ?? fallbackArtwork;
    final avatar = heroTag == null
        ? ArtistAvatar(
            name: artistName,
            artworkUrl: resolvedArtwork,
            size: avatarSize,
            borderRadius: avatarRadius,
          )
        : ArtistArtworkHero(
            tag: heroTag!,
            name: artistName,
            artworkUrl: resolvedArtwork,
            size: avatarSize,
            borderRadius: avatarRadius,
          );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        actions: [
          FavoriteArtistToggleButton(artistName: artistName),
          IconButton(
            icon: Icon(
              Icons.add,
              color: readOnlyOffline ? AppColors.textDisabled : AppColors.gold,
            ),
            tooltip: 'このアーティストの記録を追加',
            onPressed: readOnlyOffline
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CreateRecordScreen(initialArtist: artistName),
                      fullscreenDialog: true,
                    ),
                  ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  avatar,
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          artistName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.displayStyle(
                            fontSize: 30,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (artist?.genre != null)
                          Text(
                            artist!.genre!,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          '${records.length} RECORDS',
                          style: AppFonts.monoStyle(
                            fontSize: 13,
                            color: AppColors.gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: StreamingLinks(
                query: artistName,
                appleMusicUrl: artist?.appleMusicUrl,
              ),
            ),
          ),
          // iTunes にいないアーティスト（インディーズ等）は人気曲の欄ごと出さない
          if (artistAsync.isLoading ||
              artistAsync.hasError ||
              artist != null) ...[
            const SliverToBoxAdapter(child: SectionTitle('POPULAR', '人気曲')),
            _PopularSongsSliver(
              artistAsync: artistAsync,
              records: records,
              showAll: showAllSongs.value,
              collapsedCount: _collapsedSongCount,
              onToggleShowAll: () => showAllSongs.value = !showAllSongs.value,
            ),
          ],
          SliverToBoxAdapter(
            child: SectionTitle(
              'RECORDS',
              'あなたの記録',
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            ),
          ),
          if (records.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'まだ記録がありません。\n右上の＋から追加できます。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDisabled),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(top: 12, bottom: 40),
              sliver: SliverList.builder(
                itemCount: records.length,
                itemBuilder: (context, index) => RecordTicketCard(
                  record: records[index],
                  onTap: () => openRecordDetail(context, records[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PopularSongsSliver extends ConsumerWidget {
  const _PopularSongsSliver({
    required this.artistAsync,
    required this.records,
    required this.showAll,
    required this.collapsedCount,
    required this.onToggleShowAll,
  });

  final AsyncValue<ItunesArtist?> artistAsync;
  final List<Record> records;
  final bool showAll;
  final int collapsedCount;
  final VoidCallback onToggleShowAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistError = artistAsync.error;
    if (artistError != null) return _SliverError(error: artistError);
    final artist = artistAsync.asData?.value;
    if (artist == null) return const _SliverLoading();

    return ref
        .watch(topSongsProvider(artist.id))
        .when(
          loading: () => const _SliverLoading(),
          error: (e, _) => _SliverError(error: e),
          data: (songs) {
            final visible = showAll ? songs : songs.take(collapsedCount);
            return SliverPadding(
              padding: const EdgeInsets.only(top: 8),
              sliver: SliverList.list(
                children: [
                  for (final (i, song) in visible.indexed)
                    _SongTile(
                      rank: i + 1,
                      song: song,
                      heardLive: records.any(
                        (r) => setlistContainsSong(r.setlist, song.title),
                      ),
                    ),
                  if (songs.length > collapsedCount)
                    TextButton(
                      onPressed: onToggleShowAll,
                      child: Text(showAll ? '閉じる' : 'もっと見る'),
                    ),
                ],
              ),
            );
          },
        );
  }
}

class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.rank,
    required this.song,
    required this.heardLive,
  });

  final int rank;
  final ItunesSong song;

  /// 自分の記録のセトリに入っている曲。
  final bool heardLive;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              rank.toString().padLeft(2, '0'),
              style: AppFonts.monoStyle(fontSize: 12, color: AppColors.gold),
            ),
          ),
          ArtistAvatar(
            name: song.title,
            artworkUrl: song.artworkUrl,
            size: 44,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textPrimary),
      ),
      subtitle: song.albumName == null
          ? null
          : Text(
              song.albumName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (heardLive)
            Tooltip(
              message: 'ライブで聴いた曲',
              child: Icon(
                Icons.confirmation_number_rounded,
                size: 18,
                color: AppColors.gold.withValues(alpha: 0.9),
              ),
            ),
          const SizedBox(width: 8),
          PreviewPlayButton(previewUrl: song.previewUrl, size: 34),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SongDetailScreen(
            artistName: song.artistName,
            title: song.title,
            song: song,
          ),
        ),
      ),
    );
  }
}

class _SliverError extends StatelessWidget {
  const _SliverError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          toUserFriendlyMessage(error),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _SliverLoading extends StatelessWidget {
  const _SliverLoading();

  @override
  Widget build(BuildContext context) {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.gold,
          ),
        ),
      ),
    );
  }
}
