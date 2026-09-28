import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/core/widgets/decoded_network_image.dart';
import 'package:recolle/core/widgets/fullscreen_image_viewer.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/artist_avatar.dart';
import 'package:recolle/features/favorites/widgets/favorite_artist_toggle_button.dart';
import 'package:recolle/features/music/screens/artist_detail_screen.dart';
import 'package:recolle/features/music/screens/song_detail_screen.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_actions.dart';
import 'package:recolle/features/records/record_timeline.dart';
import 'package:recolle/features/records/share/share_record_sheet.dart';
import 'package:recolle/features/records/widgets/event_countdown.dart';
import 'package:recolle/features/records/widgets/ticket_stub_card.dart';

enum _MoreAction { delete }

class DetailScreen extends ConsumerStatefulWidget {
  const DetailScreen({super.key, required this.record});

  final Record record;

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  late Record _record;

  @override
  void initState() {
    super.initState();
    _record = widget.record;
  }

  @override
  void didUpdateWidget(covariant DetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.id != widget.record.id) {
      _record = widget.record;
    }
  }

  Future<void> _edit() async {
    final updated = await openRecordEditor(context, recordToEdit: _record);
    if (updated != null && mounted) setState(() => _record = updated);
  }

  Future<void> _showMore() async {
    final action = await showActionSheet<_MoreAction>(
      context,
      actions: const [
        SheetAction(
          label: '記録を削除',
          value: _MoreAction.delete,
          isDestructive: true,
        ),
      ],
    );
    if (action != _MoreAction.delete || !mounted) return;
    final deleted = await confirmAndDeleteRecord(context, ref, _record);
    if (deleted && mounted) Navigator.of(context).pop();
  }

  void _openArtist([String? name]) {
    Navigator.push(
      context,
      CupertinoPageRoute<void>(
        builder: (_) =>
            ArtistDetailScreen(artistName: name ?? _record.artistOrAuthor),
      ),
    );
  }

  Widget _actSection(RecordAct act) {
    return InsetGroupedSection(
      children: [
        GroupedRow(
          leading: Icon(
            act.isMain ? CupertinoIcons.star_fill : CupertinoIcons.music_mic,
            size: 20,
            color: act.isMain
                ? context.colors.accent
                : context.colors.textSecondary,
          ),
          title: act.artist,
          titleColor: act.isMain ? context.colors.accent : null,
          additionalInfo: act.songs.isEmpty
              ? null
              : Text(
                  '${act.songs.length}曲',
                  style: AppFonts.monoStyle(
                    fontSize: 13,
                    color: context.colors.textSecondary,
                  ),
                ),
          onTap: () => _openArtist(act.artist),
        ),
        ..._songRows(context, artistName: act.artist, songs: act.songs),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    final readOnlyOffline = ref.watch(isOfflineReadOnlyProvider);
    final isLive = record.type == RecordType.live;
    final isUpcoming = splitByDate([
      record,
    ], DateTime.now()).upcoming.isNotEmpty;
    final songs = splitSetlist(record.setlist);
    final acts = record.acts;
    final mcMemo = record.mcMemo?.trim() ?? '';
    final impressions = record.impressions?.trim() ?? '';
    final missing = [
      if (isLive && record.performances.every((a) => a.songs.isEmpty)) 'セットリスト',
      if (isLive && mcMemo.isEmpty) 'MCメモ',
      if (impressions.isEmpty) '感想',
    ];
    final artworkUrl = ref
        .watch(favoriteArtistsProvider)
        .asData
        ?.value
        .where((f) => artistMatches(record.artistOrAuthor, f.name))
        .firstOrNull
        ?.artworkUrl;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        actions: [
          NavBarIconButton(
            icon: CupertinoIcons.square_arrow_up,
            semanticLabel: 'シェア画像を作る',
            onPressed: () => showShareRecordSheet(context, record),
          ),
          NavBarTextButton(
            label: '編集',
            onPressed: readOnlyOffline ? null : _edit,
          ),
          NavBarIconButton(
            icon: CupertinoIcons.ellipsis_circle,
            semanticLabel: 'その他の操作',
            onPressed: readOnlyOffline ? null : _showMore,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: 32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _TicketImage(record: record),
          _Header(
            record: record,
            artworkUrl: artworkUrl,
            // 対バン・フェスは出演者ごとの欄から各アーティストへ飛ぶ
            onArtistTap: isLive && acts.isEmpty ? _openArtist : null,
          ),
          if (isUpcoming)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                decoration: BoxDecoration(
                  color: context.colors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: context.colors.accent.withValues(alpha: 0.35),
                  ),
                ),
                child: EventCountdown(record: record),
              ),
            ),
          TicketStubCard(record: record),
          if (acts.isNotEmpty) ...[
            _SectionHeading(
              en: 'LINEUP',
              ja: '出演者',
              trailing: '${acts.length}組',
            ),
            if (record.dayCount > 1)
              for (var day = 1; day <= record.dayCount; day++) ...[
                _DaySubheading(
                  day: day,
                  date: DateTime(
                    record.date.year,
                    record.date.month,
                    record.date.day + day - 1,
                  ),
                ),
                for (final act in acts)
                  if ((act.day ?? 1).clamp(1, record.dayCount) == day)
                    _actSection(act),
              ]
            else
              for (final act in acts) _actSection(act),
          ] else if (songs.isNotEmpty) ...[
            _SectionHeading(
              en: 'SETLIST',
              ja: 'セットリスト',
              trailing: '${songs.length}曲',
            ),
            InsetGroupedSection(
              children: _songRows(
                context,
                artistName: record.artistOrAuthor,
                songs: songs,
              ),
            ),
          ],
          if (isLive && mcMemo.isNotEmpty)
            _NoteSection(
              en: 'MC MEMO',
              ja: 'MCメモ',
              icon: CupertinoIcons.chat_bubble_2,
              text: mcMemo,
            ),
          if (impressions.isNotEmpty)
            _NoteSection(
              en: 'NOTES',
              ja: '感想',
              icon: CupertinoIcons.pencil_outline,
              text: impressions,
            ),
          if (missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
              child: Text(
                '${missing.join('・')}は右上の「編集」から追加できます',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textDisabled,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

List<Widget> _songRows(
  BuildContext context, {
  required String artistName,
  required List<String> songs,
}) => [
  for (final (i, song) in songs.indexed)
    GroupedRow(
      leading: Text(
        (i + 1).toString().padLeft(2, '0'),
        style: AppFonts.monoStyle(fontSize: 14, color: context.colors.accent),
      ),
      title: song,
      onTap: () => Navigator.push(
        context,
        CupertinoPageRoute<void>(
          builder: (_) => SongDetailScreen(artistName: artistName, title: song),
        ),
      ),
    ),
];

/// 種別・タイトル・アーティスト。ライブならアーティスト名から詳細へ飛べる。
class _Header extends StatelessWidget {
  const _Header({
    required this.record,
    required this.artworkUrl,
    required this.onArtistTap,
  });

  final Record record;
  final String? artworkUrl;
  final VoidCallback? onArtistTap;

  static IconData _iconFor(RecordType type) => switch (type) {
    RecordType.live => CupertinoIcons.music_mic,
    RecordType.movie => CupertinoIcons.film,
    RecordType.book => CupertinoIcons.book,
    RecordType.other => CupertinoIcons.tickets,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLive = record.type == RecordType.live;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconFor(record.type), size: 13, color: colors.accent),
                const SizedBox(width: 5),
                Text(
                  record.type.name.toUpperCase(),
                  style: AppFonts.monoStyle(
                    fontSize: 11,
                    color: colors.accent,
                  ).copyWith(letterSpacing: 1.6),
                ),
                const SizedBox(width: 6),
                Text(
                  record.eventFormat.hasMultipleActs
                      ? '${record.typeLabel}・${record.eventFormat.label}'
                      : record.typeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              record.title,
              style: AppFonts.titleStyle(
                fontSize: 24,
                color: colors.textPrimary,
              ).copyWith(height: 1.2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: onArtistTap,
                  child: Row(
                    children: [
                      ArtistAvatar(
                        name: record.artistOrAuthor,
                        artworkUrl: artworkUrl,
                        size: 32,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          record.artistOrAuthor,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isLive
                                ? colors.accent
                                : colors.textSecondary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (onArtistTap != null)
                        Icon(
                          CupertinoIcons.chevron_forward,
                          size: 15,
                          color: colors.accent,
                        ),
                    ],
                  ),
                ),
              ),
              if (record.acts.isEmpty)
                FavoriteArtistToggleButton(artistName: record.artistOrAuthor),
            ],
          ),
        ],
      ),
    );
  }
}

/// 複数日のフェスの出演者を日ごとに分ける小見出し。
class _DaySubheading extends StatelessWidget {
  const _DaySubheading({required this.day, required this.date});

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  final int day;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 20, 6),
      child: Text(
        'DAY $day　${date.month}月${date.day}日 (${_weekdays[date.weekday - 1]})',
        style: AppFonts.monoStyle(fontSize: 12, color: colors.accent),
      ),
    );
  }
}

/// セトリやメモの上に置く、英字と和名の見出し。
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.en, required this.ja, this.trailing});

  final String en;
  final String ja;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            en,
            style: AppFonts.displayStyle(
              fontSize: 20,
              color: colors.accent,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(width: 8),
          Text(ja, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing!,
              style: AppFonts.monoStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// MCメモ・感想のカード。左端のアクセントの線で本文を引き立てる。
class _NoteSection extends StatelessWidget {
  const _NoteSection({
    required this.en,
    required this.ja,
    required this.icon,
    required this.text,
  });

  final String en;
  final String ja;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(en: en, ja: ja),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ColoredBox(
                  color: colors.accent.withValues(alpha: 0.7),
                  child: const SizedBox(width: 3),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 16, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Icon(icon, size: 16, color: colors.accent),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SelectableText(
                            text,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 16,
                              height: 1.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// チケット画像。元の縦横比で全体を見せ、タップで全画面表示する。
class _TicketImage extends StatelessWidget {
  const _TicketImage({required this.record});

  final Record record;

  @override
  Widget build(BuildContext context) {
    if (record.ticketImageUrl.isEmpty) return const SizedBox.shrink();
    final heroTag = 'ticket-image-${record.id}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: context.colors.shadow,
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              onTap: () => FullscreenImageViewer.open(
                context,
                url: record.ticketImageUrl,
                heroTag: heroTag,
              ),
              child: Hero(
                tag: heroTag,
                child: DecodedNetworkImage(
                  url: record.ticketImageUrl,
                  logicalWidth: constraints.maxWidth,
                  fit: BoxFit.fitWidth,
                  placeholderHeight: 240,
                  errorBuilder: (context, error, stackTrace) => SizedBox(
                    height: 200,
                    child: ColoredBox(
                      color: context.colors.card,
                      child: Icon(
                        CupertinoIcons.photo,
                        size: 44,
                        color: context.colors.textDisabled,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
