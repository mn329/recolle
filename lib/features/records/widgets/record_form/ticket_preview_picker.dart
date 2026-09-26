import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:recolle/components/record_ticket_card.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/core/widgets/decoded_network_image.dart';
import 'package:recolle/features/records/models/record.dart';

enum _ImageAction { pick, remove }

/// 入力中の内容をホームのチケットと同じ見た目で見せ、タップで券面画像を選ばせる。
class TicketPreviewPicker extends StatelessWidget {
  const TicketPreviewPicker({
    super.key,
    required this.type,
    required this.title,
    required this.artistOrAuthor,
    required this.date,
    required this.onPickImage,
    required this.onRemoveImage,
    this.localImage,
    this.remoteImageUrl,
    this.endDate,
  });

  final RecordType type;
  final String title;
  final String artistOrAuthor;
  final DateTime date;

  /// 複数日の公演の最終日。
  final DateTime? endDate;

  /// 新しく選んだ画像。[remoteImageUrl] より優先して表示する。
  final File? localImage;

  /// 保存済みの画像（編集時）。
  final String? remoteImageUrl;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;

  bool get _hasImage =>
      localImage != null || (remoteImageUrl?.isNotEmpty ?? false);

  Future<void> _onTap(BuildContext context) async {
    if (!_hasImage) {
      onPickImage();
      return;
    }
    final action = await showActionSheet<_ImageAction>(
      context,
      title: 'チケット画像',
      actions: const [
        SheetAction(label: '写真を選び直す', value: _ImageAction.pick),
        SheetAction(
          label: '画像を外す',
          value: _ImageAction.remove,
          isDestructive: true,
        ),
      ],
    );
    switch (action) {
      case _ImageAction.pick:
        onPickImage();
      case _ImageAction.remove:
        onRemoveImage();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trimmedTitle = title.trim();
    final trimmedArtist = artistOrAuthor.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: _hasImage ? 'チケット画像を変更' : 'チケット画像を追加',
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            pressedOpacity: 0.8,
            onPressed: () => _onTap(context),
            child: Stack(
              children: [
                TicketFace(
                  title: trimmedTitle.isEmpty
                      ? type.titleFieldLabel
                      : trimmedTitle,
                  artistOrAuthor: trimmedArtist.isEmpty
                      ? type.creatorFieldLabel
                      : trimmedArtist,
                  date: date,
                  endDate: endDate,
                  background: _buildBackground(),
                ),
                Positioned(
                  right: 10,
                  top: 8,
                  child: _ImageBadge(hasImage: _hasImage),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'ホームにはこのチケットで並びます。タップで券面の写真を設定できます。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildBackground() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final file = localImage;
        if (file != null) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          return Image.file(
            file,
            fit: BoxFit.cover,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            cacheWidth: (constraints.maxWidth * dpr).round(),
          );
        }
        final url = remoteImageUrl;
        if (url != null && url.isNotEmpty) {
          return DecodedNetworkImage(
            url: url,
            logicalWidth: constraints.maxWidth,
            logicalHeight: constraints.maxHeight,
            errorBuilder: (_, _, _) => ColoredBox(color: context.colors.card),
          );
        }
        return ColoredBox(color: context.colors.card);
      },
    );
  }
}

class _ImageBadge extends StatelessWidget {
  const _ImageBadge({required this.hasImage});

  final bool hasImage;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.accent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasImage ? CupertinoIcons.photo : CupertinoIcons.camera_fill,
              size: 13,
              color: context.colors.onAccent,
            ),
            const SizedBox(width: 4),
            Text(
              hasImage ? '変更' : '券面を追加',
              style: TextStyle(
                fontSize: 11,
                color: context.colors.onAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
