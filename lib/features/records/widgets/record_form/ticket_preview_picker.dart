import 'dart:io';

import 'package:flutter/material.dart';
import 'package:recolle/components/record_ticket_card.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/widgets/decoded_network_image.dart';
import 'package:recolle/features/records/models/record.dart';

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
  });

  final RecordType type;
  final String title;
  final String artistOrAuthor;
  final DateTime date;

  /// 新しく選んだ画像。[remoteImageUrl] より優先して表示する。
  final File? localImage;

  /// 保存済みの画像（編集時）。
  final String? remoteImageUrl;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;

  bool get _hasImage =>
      localImage != null || (remoteImageUrl?.isNotEmpty ?? false);

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
          child: GestureDetector(
            onTap: onPickImage,
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
                  background: _buildBackground(),
                ),
                if (!_hasImage)
                  const Positioned(right: 10, top: 8, child: _AddImageBadge()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                'ホームにはこのチケットで並びます',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onPickImage,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(_hasImage ? '画像を変更' : '画像を追加'),
              style: _compactButtonStyle(AppColors.gold),
            ),
            if (_hasImage)
              TextButton(
                onPressed: onRemoveImage,
                style: _compactButtonStyle(AppColors.textSecondary),
                child: const Text('外す'),
              ),
          ],
        ),
      ],
    );
  }

  static ButtonStyle _compactButtonStyle(Color color) => TextButton.styleFrom(
    foregroundColor: color,
    visualDensity: VisualDensity.compact,
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
  );

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
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: AppColors.surfaceLight),
          );
        }
        return const ColoredBox(color: AppColors.surfaceLight);
      },
    );
  }
}

class _AddImageBadge extends StatelessWidget {
  const _AddImageBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_a_photo_outlined, size: 14, color: AppColors.gold),
            SizedBox(width: 4),
            Text(
              '券面を追加',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.gold,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
