import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/components/record_ticket_list.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/core/widgets/section_title.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/record_stats.dart';

/// 振り返りの集計から開く、行ったライブの一覧（新しい順）。
///
/// 集計と同じ条件で数え直すので、ここから記録を編集して戻っても一覧が食い違わない。
class LiveListScreen extends ConsumerWidget {
  const LiveListScreen({super.key, this.year, this.month, this.artist});

  /// null なら全期間。
  final int? year;

  /// 1〜12。null なら月で絞らない。[year] が null なら全期間のその月。
  final int? month;

  /// null ならアーティストで絞らない。
  final String? artist;

  String get _title {
    final period = switch ((year, month)) {
      (final y?, final m?) => '$y年$m月',
      (final y?, null) => '$y年',
      (null, final m?) => '$m月（全期間）',
      (null, null) => 'これまで',
    };
    return [?artist, '$periodのライブ'].join('・');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(recordsProvider);
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(),
      body: CustomScrollView(
        slivers: recordsAsync.when(
          data: (records) {
            final lives =
                computeStats(
                      filterByArtist(records, artist),
                      now: DateTime.now(),
                      year: year,
                      artist: artist,
                    ).lives
                    .where((r) => month == null || r.date.month == month)
                    .toList();
            return [
              SliverToBoxAdapter(
                child: SectionTitle(
                  'LIVES',
                  '$_title・${lives.length}回',
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                ),
              ),
              SliverRecordTicketList(
                records: lives,
                emptyMessage: 'この期間に行ったライブの記録はありません',
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
    );
  }
}
