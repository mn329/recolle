import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/components/record_ticket_card.dart';
import 'package:recolle/components/record_ticket_list.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/section_title.dart';
import 'package:recolle/features/favorites/widgets/artist_avatar.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:recolle/features/music/screens/artist_detail_screen.dart';
import 'package:recolle/features/music/widgets/preview_play_button.dart';
import 'package:recolle/features/music/widgets/streaming_links.dart';
import 'package:recolle/features/records/providers/records_provider.dart';

/// 曲詳細: ジャケット・収録情報、ストリーミングへのリンク、この曲を聴いた記録。
class SongDetailScreen extends ConsumerWidget {
  const SongDetailScreen({
    super.key,
    required this.artistName,
    required this.title,
    this.song,
  });

  final String artistName;
  final String title;

  /// 既に iTunes の曲が分かっていれば渡す（再検索しない）。
  final ItunesSong? song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ItunesSong?> songAsync = song != null
        ? AsyncData(song)
        : ref.watch(itunesSongProvider((artistName: artistName, title: title)));
    final resolved = songAsync.asData?.value;
    final heardRecords = (ref.watch(recordsProvider).asData?.value ?? const [])
        .where(
          (r) =>
              artistMatches(r.artistOrAuthor, artistName) &&
              setlistContainsSong(r.setlist, title),
        )
        .toList();

    final artworkSize = (MediaQuery.sizeOf(context).width - 96).clamp(
      160.0,
      300.0,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: songAsync.isLoading
                        ? SizedBox.square(
                            dimension: artworkSize,
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.gold,
                              ),
                            ),
                          )
                        : ArtistAvatar(
                            name: title,
                            artworkUrl: resolved?.artworkUrl,
                            size: artworkSize,
                            borderRadius: BorderRadius.circular(16),
                          ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ArtistDetailScreen(
                          artistName: artistName,
                          itunesArtistId: resolved?.artistId,
                        ),
                      ),
                    ),
                    child: Text(
                      artistName,
                      style: AppFonts.displayStyle(
                        fontSize: 20,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                  if (resolved != null) _SongMeta(song: resolved),
                  if (resolved?.previewUrl != null) ...[
                    const SizedBox(height: 16),
                    PreviewPlayButton(
                      previewUrl: resolved!.previewUrl,
                      size: 64,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '30秒試聴',
                      style: TextStyle(
                        color: AppColors.textDisabled,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (songAsync.hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        toUserFriendlyMessage(songAsync.error),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  StreamingLinks(
                    query: '$title $artistName',
                    appleMusicUrl: resolved?.appleMusicUrl,
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: SectionTitle('LIVE HISTORY', 'この曲を聴いた記録'),
          ),
          if (heardRecords.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'セトリにこの曲が入った記録はまだありません',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDisabled),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(top: 12, bottom: 40),
              sliver: SliverList.builder(
                itemCount: heardRecords.length,
                itemBuilder: (context, index) => RecordTicketCard(
                  record: heardRecords[index],
                  onTap: () => openRecordDetail(context, heardRecords[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SongMeta extends StatelessWidget {
  const _SongMeta({required this.song});

  final ItunesSong song;

  @override
  Widget build(BuildContext context) {
    final duration = song.duration;
    final parts = [
      if (song.releaseDate != null) '${song.releaseDate!.year}',
      if (duration != null)
        '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
    ];
    return Column(
      children: [
        if (song.albumName != null)
          Text(
            song.albumName!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        if (parts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              parts.join('  ·  '),
              style: AppFonts.monoStyle(
                fontSize: 12,
                color: AppColors.textDisabled,
              ),
            ),
          ),
      ],
    );
  }
}
