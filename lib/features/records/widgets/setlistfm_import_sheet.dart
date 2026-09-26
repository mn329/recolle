import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/music/data/setlistfm_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';

/// setlist.fm から公演を選び、その曲目を返す。キャンセル時は null。
Future<List<String>?> showSetlistFmImportSheet(
  BuildContext context, {
  required String artistName,
  required DateTime date,
}) {
  return showCupertinoSheet<List<String>>(
    context: context,
    builder: (_) => _SetlistFmImportSheet(artistName: artistName, date: date),
  );
}

class _SetlistFmImportSheet extends HookConsumerWidget {
  const _SetlistFmImportSheet({required this.artistName, required this.date});

  final String artistName;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // まず公演日で探し、見つからなければ日付なし（最近の公演）に広げられるようにする
    final filterByDate = useState(true);
    final retryToken = useState(0);
    final future = useMemoized(
      () => ref
          .read(setlistFmClientProvider)
          .search(
            artistName: artistName,
            date: filterByDate.value ? date : null,
          ),
      [filterByDate.value, retryToken.value],
    );
    final snapshot = useFuture(future);
    final isLocalizing = useState(false);

    Future<void> pick(SetlistSummary setlist) async {
      if (isLocalizing.value) return;
      isLocalizing.value = true;
      var songs = setlist.songs;
      try {
        final japanese = await ref
            .read(itunesClientProvider)
            .localizeSongTitles(artistName: artistName, titles: songs);
        songs = [for (final s in songs) japanese[s] ?? s];
      } catch (e) {
        // 日本語化は補助機能なので、失敗しても元の表記で取り込む
        debugPrint('Song title localization failed: $e');
      }
      if (context.mounted) Navigator.of(context).pop(songs);
    }

    return CupertinoPageScaffold(
      backgroundColor: AppColors.background,
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.background,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 44),
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'キャンセル',
            style: TextStyle(color: AppColors.gold, fontSize: 17),
          ),
        ),
        middle: const Text('setlist.fm から取り込む'),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                filterByDate.value
                    ? '$artistName・${_formatDate(date)} の公演'
                    : '$artistName の最近の公演',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: isLocalizing.value
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CupertinoActivityIndicator(radius: 14),
                          SizedBox(height: 16),
                          Text(
                            '曲名を日本語表記に変換しています…',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : _buildBody(
                      context,
                      snapshot,
                      filterByDate,
                      retryToken,
                      pick,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncSnapshot<List<SetlistSummary>> snapshot,
    ValueNotifier<bool> filterByDate,
    ValueNotifier<int> retryToken,
    ValueChanged<SetlistSummary> onPick,
  ) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }
    if (snapshot.hasError) {
      return IosEmptyState(
        icon: CupertinoIcons.wifi_exclamationmark,
        message: toUserFriendlyMessage(snapshot.error),
        actionLabel: '再試行',
        onAction: () => retryToken.value++,
      );
    }

    final setlists = snapshot.data ?? const <SetlistSummary>[];
    if (setlists.isEmpty) {
      return filterByDate.value
          ? IosEmptyState(
              icon: CupertinoIcons.calendar,
              message: 'この日のセットリストは登録されていません。',
              actionLabel: '日付を指定せずに探す',
              onAction: () => filterByDate.value = false,
            )
          : const IosEmptyState(
              icon: CupertinoIcons.music_note_list,
              message: 'セットリストが見つかりませんでした。',
            );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: setlists.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == setlists.length) {
          return const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Setlist data from setlist.fm',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDisabled, fontSize: 11),
            ),
          );
        }
        final s = setlists[index];
        return _SetlistCard(setlist: s, onTap: () => onPick(s));
      },
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}

class _SetlistCard extends StatelessWidget {
  const _SetlistCard({required this.setlist, required this.onTap});

  final SetlistSummary setlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = setlist.eventDate;
    final place = [
      setlist.venueName,
      setlist.cityName,
    ].where((e) => e.isNotEmpty).join(' / ');
    final preview = setlist.songs.take(3).join('、');

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (date != null)
                        Text(
                          _SetlistFmImportSheet._formatDate(date),
                          style: AppFonts.monoStyle(
                            fontSize: 13,
                            color: AppColors.gold,
                          ),
                        ),
                      const Spacer(),
                      Text(
                        '${setlist.songs.length}曲',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (place.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      place,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (setlist.tourName != null)
                    Text(
                      setlist.tourName!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    '$preview${setlist.songs.length > 3 ? ' ほか' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              CupertinoIcons.chevron_forward,
              size: 16,
              color: AppColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}
