import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/widgets/decoded_network_image.dart';
import 'package:recolle/core/widgets/fullscreen_image_viewer.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/utils/japanese_date_format.dart';
import 'package:recolle/core/widgets/section_title.dart';
import 'package:recolle/features/favorites/widgets/favorite_artist_toggle_button.dart';
import 'package:recolle/features/music/screens/artist_detail_screen.dart';
import 'package:recolle/features/music/screens/song_detail_screen.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/screens/create_record_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final record = _record;
    final readOnlyOffline = ref.watch(isOfflineReadOnlyProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.edit_outlined,
              color: readOnlyOffline ? AppColors.textDisabled : null,
            ),
            tooltip: readOnlyOffline ? 'オフラインでは編集できません' : '編集',
            onPressed: readOnlyOffline
                ? null
                : () async {
                    final updated = await Navigator.push<Record>(
                      context,
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (context) =>
                            CreateRecordScreen(recordToEdit: record),
                      ),
                    );
                    if (updated != null && mounted) {
                      setState(() => _record = updated);
                    }
                  },
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: readOnlyOffline ? AppColors.textDisabled : null,
            ),
            tooltip: readOnlyOffline ? 'オフラインでは削除できません' : '削除',
            onPressed: readOnlyOffline
                ? null
                : () => _confirmAndDelete(context, ref),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 2. Large Ticket Image（元の縦横比で全体を表示し、タップで拡大）
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final heroTag = 'ticket-image-${record.id}';
                  return GestureDetector(
                    onTap: record.ticketImageUrl.isEmpty
                        ? null
                        : () => FullscreenImageViewer.open(
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
                        placeholderHeight: 300,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 300,
                            color: AppColors.surfaceLight,
                            child: const Icon(
                              Icons.broken_image,
                              size: 50,
                              color: AppColors.textDisabled,
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // 3. Basic Info Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: AppColors.gold.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              // iTunes のカタログは音楽のみなので、ライブのときだけ詳細へ飛べる
                              onTap: record.type == RecordType.live
                                  ? () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ArtistDetailScreen(
                                          artistName: record.artistOrAuthor,
                                        ),
                                      ),
                                    )
                                  : null,
                              child: Text.rich(
                                TextSpan(
                                  text: record.artistOrAuthor,
                                  children: [
                                    if (record.type == RecordType.live)
                                      const WidgetSpan(
                                        alignment: PlaceholderAlignment.middle,
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          color: AppColors.gold,
                                        ),
                                      ),
                                  ],
                                ),
                                style: const TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          FavoriteArtistToggleButton(
                            artistName: record.artistOrAuthor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Title
                      Text(
                        record.title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: AppColors.textDisabled, height: 1),
                      const SizedBox(height: 16),
                      // Date and Source
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formatJapaneseDate(record.date),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          if (record.ticketSource != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppColors.textDisabled,
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                record.ticketSource!,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // 4. Reports
            if (record.type == RecordType.live) ...[
              const SectionTitle('SETLIST', 'セトリ'),
              _buildSetlistContent(record),
              const SizedBox(height: 24),
              const SectionTitle('MC MEMO', 'MCメモ'),
              _buildSectionContent(record.mcMemo),
              const SizedBox(height: 24),
            ],

            const SectionTitle('IMPRESSIONS', '感想'),
            _buildSectionContent(record.impressions),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionContent(String? content) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Text(
        (content == null || content.isEmpty) ? '未入力' : content,
        style: TextStyle(
          color: (content == null || content.isEmpty)
              ? AppColors.textDisabled
              : AppColors.textPrimary,
          fontSize: 15,
          height: 1.6,
        ),
      ),
    );
  }

  /// セットリストを改行で分割し、番号付きで1曲ずつ表示する。タップで曲詳細へ。
  Widget _buildSetlistContent(Record record) {
    final setlistText = record.setlist;
    final lines = (setlistText == null || setlistText.isEmpty)
        ? <String>[]
        : setlistText
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();

    if (lines.isEmpty) {
      return _buildSectionContent(null);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SongDetailScreen(
                    artistName: record.artistOrAuthor,
                    title: lines[i],
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        (i + 1).toString().padLeft(2, '0'),
                        style: AppFonts.monoStyle(
                          fontSize: 14,
                          color: AppColors.gold,
                        ).copyWith(height: 1.75),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        lines[i],
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.textDisabled.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('記録を削除しますか？'),
        content: Text(
          '「${_record.title}」を削除すると元に戻せません。',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(recordsRepositoryProvider).deleteRecord(_record.id);

      if (!context.mounted) return;
      ref.invalidate(recordsProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('記録を削除しました')));
      Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除に失敗しました。${toUserFriendlyMessage(e)}')),
        );
      }
    }
  }
}
