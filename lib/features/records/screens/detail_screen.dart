import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/japanese_date_format.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/core/widgets/decoded_network_image.dart';
import 'package:recolle/core/widgets/fullscreen_image_viewer.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/widgets/favorite_artist_toggle_button.dart';
import 'package:recolle/features/music/screens/artist_detail_screen.dart';
import 'package:recolle/features/music/screens/song_detail_screen.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_actions.dart';

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

  void _openArtist() {
    Navigator.push(
      context,
      CupertinoPageRoute<void>(
        builder: (_) => ArtistDetailScreen(artistName: _record.artistOrAuthor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    final readOnlyOffline = ref.watch(isOfflineReadOnlyProvider);
    final isLive = record.type == RecordType.live;
    final songs = (record.setlist ?? '')
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        actions: [
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.typeLabel,
                        style: AppFonts.monoStyle(
                          fontSize: 12,
                          color: AppColors.gold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // iTunes のカタログは音楽のみなので、ライブのときだけ詳細へ飛べる
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: isLive ? _openArtist : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                record.artistOrAuthor,
                                style: TextStyle(
                                  color: isLive
                                      ? AppColors.gold
                                      : AppColors.textSecondary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isLive)
                              const Icon(
                                CupertinoIcons.chevron_forward,
                                size: 16,
                                color: AppColors.gold,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                FavoriteArtistToggleButton(artistName: record.artistOrAuthor),
              ],
            ),
          ),
          InsetGroupedSection(
            hasLeading: false,
            children: [
              GroupedRow(
                title: isLive ? '公演日' : '日付',
                additionalInfo: Text(
                  formatJapaneseDate(record.date, includeWeekday: true),
                  style: AppFonts.monoStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (record.ticketSource != null)
                GroupedRow(
                  title: 'チケット取得元',
                  additionalInfo: Text(
                    record.ticketSource!,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          if (isLive) ...[
            const SizedBox(height: 16),
            if (songs.isEmpty)
              const _TextSection(header: 'セットリスト', text: null)
            else
              InsetGroupedSection(
                header: 'セットリスト・${songs.length}曲',
                children: [
                  for (final (i, song) in songs.indexed)
                    GroupedRow(
                      leading: Text(
                        (i + 1).toString().padLeft(2, '0'),
                        style: AppFonts.monoStyle(
                          fontSize: 14,
                          color: AppColors.gold,
                        ),
                      ),
                      title: song,
                      onTap: () => Navigator.push(
                        context,
                        CupertinoPageRoute<void>(
                          builder: (_) => SongDetailScreen(
                            artistName: record.artistOrAuthor,
                            title: song,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            _TextSection(header: 'MCメモ', text: record.mcMemo),
          ],
          const SizedBox(height: 16),
          _TextSection(header: '感想', text: record.impressions),
        ],
      ),
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
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 24,
              offset: Offset(0, 12),
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
                  errorBuilder: (context, error, stackTrace) => const SizedBox(
                    height: 200,
                    child: ColoredBox(
                      color: AppColors.card,
                      child: Icon(
                        CupertinoIcons.photo,
                        size: 44,
                        color: AppColors.textDisabled,
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

/// 見出し付きの文章カード。未入力なら薄く「未入力」と出す。
class _TextSection extends StatelessWidget {
  const _TextSection({required this.header, required this.text});

  final String header;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final content = text?.trim() ?? '';
    return InsetGroupedSection(
      header: header,
      hasLeading: false,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: SelectableText(
            content.isEmpty ? '未入力' : content,
            style: TextStyle(
              color: content.isEmpty
                  ? AppColors.textDisabled
                  : AppColors.textPrimary,
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}
