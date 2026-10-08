import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/components/record_ticket_list.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/app_background.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/core/widgets/section_title.dart';
import 'package:recolle/features/music/screens/song_detail_screen.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/record_stats.dart';
import 'package:recolle/features/records/widgets/ranking_section.dart';

/// 振り返りの「よく行った会場」から開く、その会場で聴いた曲と行ったライブ。
///
/// 振り返りで選んでいた年・アーティストの絞り込みを引き継ぐ。
class VenueDetailScreen extends ConsumerWidget {
  const VenueDetailScreen({
    super.key,
    required this.venue,
    this.year,
    this.artist,
  });

  final String venue;

  /// null なら全期間。
  final int? year;

  /// null ならアーティストで絞らない。
  final String? artist;

  static const _songLimit = 20;

  String get _scope => [?artist, if (year case final y?) '$y年'].join('・');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(recordsProvider);
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(),
        body: CustomScrollView(
          slivers: recordsAsync.when(
            data: (records) {
              final stats = computeStats(
                filterByVenue(filterByArtist(records, artist), venue),
                now: DateTime.now(),
                year: year,
                artist: artist,
                rankingLimit: _songLimit,
              );
              return [
                SliverToBoxAdapter(
                  child: SectionTitle(
                    'VENUE',
                    venue,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      [
                        if (_scope.isNotEmpty) _scope,
                        '${stats.liveCount}回行きました',
                      ].join('・'),
                      style: TextStyle(
                        fontSize: 14,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: stats.topSongs.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                          child: Text(
                            'この会場のライブには、セトリの記録がまだありません。',
                            style: TextStyle(
                              fontSize: 14,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        )
                      : RankingSection(
                          header: 'この会場で聴いた曲',
                          rows: [
                            for (final s in stats.topSongs)
                              (
                                title: s.title,
                                subtitle: artist == null ? s.artist : null,
                                count: s.count,
                                onTap: () => Navigator.push(
                                  context,
                                  CupertinoPageRoute<void>(
                                    builder: (_) => SongDetailScreen(
                                      artistName: s.artist,
                                      title: s.title,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                SliverToBoxAdapter(
                  child: SectionTitle(
                    'LIVES',
                    'この会場で行ったライブ・${stats.liveCount}回',
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  ),
                ),
                SliverRecordTicketList(
                  records: stats.lives,
                  emptyMessage: 'この会場で行ったライブの記録はありません',
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 32 + MediaQuery.paddingOf(context).bottom,
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
                  onAction: () => ref.invalidate(recordsProvider),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
