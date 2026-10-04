import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:recolle/components/record_ticket_card.dart';
import 'package:recolle/core/constants/ticket_image_settings.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/widgets/decoded_network_image.dart';
import 'package:recolle/features/records/data/records_repository.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/record_form_state.dart';

/// 入力中の内容をホームのチケットと同じ見た目で見せ、その下でチケット画像を選ばせる。
class TicketPreviewPicker extends StatelessWidget {
  const TicketPreviewPicker({
    super.key,
    required this.type,
    required this.title,
    required this.artistOrAuthor,
    required this.date,
    required this.images,
    required this.onAddImages,
    required this.onRemoveImage,
    required this.onMakeCover,
    this.endDate,
  });

  final RecordType type;
  final String title;
  final String artistOrAuthor;
  final DateTime date;

  /// 複数日の公演の最終日。
  final DateTime? endDate;

  /// 選んである画像。先頭が表紙。
  final List<TicketImage> images;
  final VoidCallback onAddImages;
  final ValueChanged<int> onRemoveImage;
  final ValueChanged<int> onMakeCover;

  bool get _canAdd => images.length < TicketImageSettings.maxCount;

  void _makeCover(int index) {
    HapticFeedback.selectionClick();
    onMakeCover(index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trimmedTitle = title.trim();
    final trimmedArtist = artistOrAuthor.trim();
    final cover = images.firstOrNull;
    final ticket = TicketFace(
      title: trimmedTitle.isEmpty ? type.titleFieldLabel : trimmedTitle,
      artistOrAuthor: trimmedArtist.isEmpty
          ? type.creatorFieldLabel
          : trimmedArtist,
      date: date,
      endDate: endDate,
      photoCount: images.length,
      photo: cover == null ? null : TicketImageView(image: cover),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cover == null)
          Semantics(
            button: true,
            label: 'チケット画像を追加',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              pressedOpacity: 0.8,
              onPressed: onAddImages,
              child: ticket,
            ),
          )
        else
          ticket,
        const SizedBox(height: 12),
        SizedBox(
          height: _Thumbnail.size,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              for (final (i, image) in images.indexed) ...[
                _Thumbnail(
                  image: image,
                  isCover: i == 0,
                  onMakeCover: () => _makeCover(i),
                  onRemove: () => onRemoveImage(i),
                ),
                const SizedBox(width: 8),
              ],
              if (_canAdd) _AddTile(count: images.length, onTap: onAddImages),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'ホームにはこのチケットで並びます。写真は${TicketImageSettings.maxCount}枚まで選べて、タップした写真が表紙になります。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// 保存済み・選んだばかりのどちらのチケット画像も、枠いっぱいに切り抜いて表示する。
class TicketImageView extends StatelessWidget {
  const TicketImageView({super.key, required this.image});

  final TicketImage image;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget fallback(BuildContext context, Object _, StackTrace? _) =>
            ColoredBox(color: context.colors.card);
        return switch (image) {
          PickedTicketImage(:final file) => Image.file(
            file,
            fit: BoxFit.cover,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            cacheWidth:
                (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                    .round(),
            errorBuilder: fallback,
          ),
          SavedTicketImage(:final url) => _savedImage(
            url,
            constraints,
            fallback,
          ),
        };
      },
    );
  }

  Widget _savedImage(
    String url,
    BoxConstraints constraints,
    ImageErrorWidgetBuilder errorBuilder,
  ) {
    final request = RecordsRepository.ticketImageRequest(url);
    return DecodedNetworkImage(
      url: request.url,
      headers: request.headers,
      fallbackUrl: request.url == url ? null : url,
      logicalWidth: constraints.maxWidth,
      logicalHeight: constraints.maxHeight,
      fit: BoxFit.cover,
      errorBuilder: errorBuilder,
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.image,
    required this.isCover,
    required this.onMakeCover,
    required this.onRemove,
  });

  static const double size = 64;

  final TicketImage image;
  final bool isCover;
  final VoidCallback onMakeCover;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Semantics(
          button: !isCover,
          label: isCover ? '表紙の画像' : 'チケット画像',
          hint: isCover ? null : '表紙にする',
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            pressedOpacity: 0.7,
            onPressed: isCover ? null : onMakeCover,
            child: _face(context),
          ),
        ),
        Positioned(top: 0, right: 0, child: _RemoveButton(onPressed: onRemove)),
      ],
    );
  }

  Widget _face(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            TicketImageView(image: image),
            if (isCover)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  color: colors.accent,
                  child: Text(
                    '表紙',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: colors.onAccent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '画像を外す',
      excludeSemantics: true,
      child: CupertinoButton(
        padding: const EdgeInsets.all(4),
        minimumSize: Size.zero,
        onPressed: onPressed,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xB3000000),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFFFFFF), width: 1.5),
          ),
          child: const Icon(
            CupertinoIcons.xmark,
            size: 10,
            color: Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'チケット画像を追加',
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onTap,
        child: Container(
          width: _Thumbnail.size,
          height: _Thumbnail.size,
          decoration: BoxDecoration(
            color: colors.fill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.plus, size: 20, color: colors.accent),
              const SizedBox(height: 2),
              Text(
                '$count/${TicketImageSettings.maxCount}',
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
