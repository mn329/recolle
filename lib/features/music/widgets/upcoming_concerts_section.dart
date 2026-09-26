import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/app_toast.dart';
import 'package:recolle/core/widgets/section_title.dart';
import 'package:recolle/features/music/data/concert_discovery_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:recolle/features/music/widgets/google_search_suggestions.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_actions.dart';
import 'package:recolle/features/records/ticket_mail_parser.dart';
import 'package:url_launcher/url_launcher.dart';

/// アーティストの今後の公演を、生成 AI の Web 検索で探して並べる欄。
///
/// 1 回ごとに Gemini の無料枠を使うので、開いただけでは検索せず「公演を探す」を押してから読む。
class UpcomingConcertsSection extends HookConsumerWidget {
  const UpcomingConcertsSection({
    super.key,
    required this.artistName,
    required this.records,
  });

  final String artistName;

  /// このアーティストの自分の記録。同じ日の公演は「記録済み」にする。
  final List<Record> records;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = concertDiscoveryProvider(artistName);
    // このセッションで一度探したアーティストは、開き直しても結果を出す
    final requested = useState(ref.exists(provider));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('UPCOMING', 'これからの公演'),
        const SizedBox(height: 10),
        if (!requested.value)
          _IntroCard(onSearch: () => requested.value = true)
        else
          ref
              .watch(provider)
              .when(
                loading: () => const _Loading(),
                error: (error, _) => _ErrorCard(
                  message: toUserFriendlyMessage(error),
                  onRetry: () => ref.invalidate(provider),
                ),
                data: (result) => _Results(
                  artistName: artistName,
                  result: result,
                  records: records,
                ),
              ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: padding,
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.sparkles, size: 18, color: colors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Web から今後のライブ・フェス出演を AI が探します',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '結果は誤っていることがあります。登録する前に公式の告知を確認してください。',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              onPressed: onSearch,
              child: const Text('公演を探す'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          const CupertinoActivityIndicator(),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Web を検索しています…（30 秒ほどかかることがあります）',
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
          ),
          CupertinoButton(
            padding: const EdgeInsets.only(top: 8),
            minimumSize: Size.zero,
            onPressed: onRetry,
            child: Text(
              'もう一度探す',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.colors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({
    required this.artistName,
    required this.result,
    required this.records,
  });

  final String artistName;
  final ConcertDiscoveryResult result;
  final List<Record> records;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final readOnlyOffline = ref.watch(isOfflineReadOnlyProvider);
    final fetched = result.fetchedAt;
    final searchEntryPoint = result.searchEntryPoint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          padding: EdgeInsets.zero,
          child: result.concerts.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '告知されている今後の公演は見つかりませんでした。',
                    style: TextStyle(fontSize: 14, color: colors.textSecondary),
                  ),
                )
              : Column(
                  children: [
                    for (final (i, concert) in result.concerts.indexed) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 76),
                          child: SizedBox(
                            height: 0.5,
                            child: ColoredBox(color: colors.separator),
                          ),
                        ),
                      _ConcertRow(
                        concert: concert,
                        isRecorded: records.any(
                          (r) =>
                              r.date.year == concert.date.year &&
                              r.date.month == concert.date.month &&
                              r.date.day == concert.date.day,
                        ),
                        onAdd: readOnlyOffline
                            ? null
                            : () => openRecordEditor(
                                context,
                                initialType: RecordType.live,
                                prefill: TicketMailInfo(
                                  title: concert.title,
                                  artist: artistName,
                                  date: concert.date,
                                  venue: concert.venue,
                                  openTime: concert.openTime,
                                  startTime: concert.startTime,
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            'AI が Web 検索でまとめた情報です（${fetched.month}/${fetched.day} '
            '${fetched.hour.toString().padLeft(2, '0')}:'
            '${fetched.minute.toString().padLeft(2, '0')} 時点）。'
            '日時や会場は公式の告知で確認してください。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: colors.textSecondary,
            ),
          ),
        ),
        if (result.sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final source in result.sources)
                  _SourceChip(title: source.title, uri: source.uri),
              ],
            ),
          ),
        if (searchEntryPoint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: GoogleSearchSuggestions(html: searchEntryPoint),
          ),
      ],
    );
  }
}

class _ConcertRow extends StatelessWidget {
  const _ConcertRow({
    required this.concert,
    required this.isRecorded,
    required this.onAdd,
  });

  final DiscoveredConcert concert;
  final bool isRecorded;
  final VoidCallback? onAdd;

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', //
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final date = concert.date;
    final place = [?concert.venue, ?concert.city].join('・');
    final times = [
      if (concert.openTime case final open?) '開場 ${open.format()}',
      if (concert.startTime case final start?) '開演 ${start.format()}',
    ].join(' / ');
    final source = concert.sourceUrl;

    return CupertinoButton(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      minimumSize: Size.zero,
      onPressed: source == null ? null : () => _openSource(source),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Text(
                  _months[date.month - 1],
                  style: AppFonts.monoStyle(fontSize: 11, color: colors.accent),
                ),
                Text(
                  '${date.day}',
                  style: AppFonts.displayStyle(
                    fontSize: 26,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  _weekdays[date.weekday - 1],
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  concert.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                    height: 1.3,
                  ),
                ),
                if (place.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ],
                if (times.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    times,
                    style: AppFonts.monoStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                if (source != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    source.host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colors.accent),
                  ),
                ],
              ],
            ),
          ),
          if (isRecorded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '記録済み',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            )
          else
            CupertinoButton(
              padding: const EdgeInsets.all(8),
              minimumSize: Size.zero,
              onPressed: onAdd,
              child: Icon(
                CupertinoIcons.plus_circle_fill,
                size: 28,
                color: onAdd == null ? colors.textDisabled : colors.accent,
                semanticLabel: 'この公演を記録に追加',
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.title, required this.uri});

  final String title;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      minimumSize: Size.zero,
      color: colors.fill,
      borderRadius: BorderRadius.circular(12),
      onPressed: () => _openSource(uri),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.link, size: 12, color: colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

Future<void> _openSource(Uri uri) async {
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('launchUrl failed for $uri: $e');
  }
  if (!opened) AppToast.error('ページを開けませんでした');
}
