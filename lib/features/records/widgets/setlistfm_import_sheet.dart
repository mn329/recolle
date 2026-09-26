import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/features/music/data/setlistfm_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';

/// setlist.fm から公演を選び、その曲目を返す。キャンセル時は null。
Future<List<String>?> showSetlistFmImportSheet(
  BuildContext context, {
  required String artistName,
  required DateTime date,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
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

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text(
              'SETLIST.FM',
              style: AppFonts.displayStyle(fontSize: 26, color: AppColors.gold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
          if (isLocalizing.value)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                children: [
                  CircularProgressIndicator(color: AppColors.gold),
                  SizedBox(height: 16),
                  Text(
                    '曲名を日本語表記に変換しています…',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: _buildBody(
                context,
                snapshot,
                filterByDate,
                retryToken,
                pick,
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Text(
              'Setlist data from setlist.fm',
              style: TextStyle(color: AppColors.textDisabled, fontSize: 11),
            ),
          ),
        ],
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
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }
    if (snapshot.hasError) {
      return _Message(
        text: toUserFriendlyMessage(snapshot.error),
        actionLabel: '再試行',
        onAction: () => retryToken.value++,
      );
    }

    final setlists = snapshot.data ?? const <SetlistSummary>[];
    if (setlists.isEmpty) {
      return filterByDate.value
          ? _Message(
              text: 'この日のセットリストは登録されていません。',
              actionLabel: '日付を指定せずに探す',
              onAction: () => filterByDate.value = false,
            )
          : const _Message(text: 'セットリストが見つかりませんでした。');
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: setlists.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
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

    return Material(
      color: AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                    '${setlist.songs.length} SONGS',
                    style: AppFonts.monoStyle(
                      fontSize: 11,
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
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
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
                  color: AppColors.textDisabled,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
