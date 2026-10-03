import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/features/records/data/records_repository.dart';

/// 詳細画面のチケット画像。切り抜かずに全体を見せ、複数枚なら横スワイプで切り替える。
///
/// 高さは写真の縦横比に合わせ、スマホの縦画面で撮った写真のような縦長のものは
/// 画面を占領しないよう [maxHeightRatio] までに抑えて、左右をぼかした同じ写真で埋める。
class TicketImageCarousel extends StatefulWidget {
  const TicketImageCarousel({super.key, required this.urls});

  final List<String> urls;

  /// 読み込み前・読み込めなかった写真の高さ。
  static const double placeholderHeight = 220;
  static const double minHeight = 160;
  static const double maxHeight = 520;

  /// 画面の高さに対する上限の割合。
  static const double maxHeightRatio = 0.6;

  /// 幅 [width] に縦横比 [aspectRatio]（幅 / 高さ）の写真を収める高さ。
  /// 縦長の写真は [maxHeight] で止め、縦横比が分からなければ [placeholderHeight] にする。
  static double heightFor({
    required double? aspectRatio,
    required double width,
    required double maxHeight,
  }) {
    final natural = aspectRatio == null || aspectRatio <= 0
        ? placeholderHeight
        : width / aspectRatio;
    return natural.clamp(minHeight, maxHeight);
  }

  @override
  State<TicketImageCarousel> createState() => _TicketImageCarouselState();
}

class _TicketImageCarouselState extends State<TicketImageCarousel> {
  final _controller = PageController();
  int _page = 0;

  /// 読み込めた写真の縦横比（幅 / 高さ）。
  final _aspectRatios = <int, double>{};
  final _streams = <(ImageStream, ImageStreamListener)>[];
  double? _decodeWidth;

  @override
  void didUpdateWidget(TicketImageCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.urls, widget.urls)) {
      _stopListening();
      _aspectRatios.clear();
      _decodeWidth = null;
      final last = widget.urls.length - 1;
      if (last >= 0 && _page > last) {
        _page = last;
        if (_controller.hasClients) _controller.jumpToPage(last);
      }
    }
  }

  @override
  void dispose() {
    _stopListening();
    _controller.dispose();
    super.dispose();
  }

  void _stopListening() {
    for (final (stream, listener) in _streams) {
      stream.removeListener(listener);
    }
    _streams.clear();
  }

  /// 表示と同じ解像度で読み込み、縦横比が分かったら高さを合わせる。
  void _resolveAspectRatios(double width) {
    if (_decodeWidth == width) return;
    _decodeWidth = width;
    _stopListening();
    final configuration = createLocalImageConfiguration(context);
    for (final (i, url) in widget.urls.indexed) {
      final stream = _provider(url, width).resolve(configuration);
      final listener = ImageStreamListener(
        (info, _) {
          final image = info.image;
          final ratio = image.width / image.height;
          info.dispose();
          if (mounted && _aspectRatios[i] != ratio) {
            setState(() => _aspectRatios[i] = ratio);
          }
        },
        onError: (error, stackTrace) =>
            debugPrint('Failed to load ticket image: $error'),
      );
      stream.addListener(listener);
      _streams.add((stream, listener));
    }
  }

  ImageProvider _provider(String url, double width) => ResizeImage(
    _networkImage(url),
    width: (width * MediaQuery.devicePixelRatioOf(context)).round(),
  );

  static NetworkImage _networkImage(String storedUrl) {
    final request = RecordsRepository.ticketImageRequest(storedUrl);
    return NetworkImage(request.url, headers: request.headers);
  }

  double _heightOf(int index, double width, double maxHeight) =>
      TicketImageCarousel.heightFor(
        aspectRatio: _aspectRatios[index],
        width: width,
        maxHeight: maxHeight,
      );

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    final maxHeight =
        (MediaQuery.sizeOf(context).height * TicketImageCarousel.maxHeightRatio)
            .clamp(
              TicketImageCarousel.minHeight,
              TicketImageCarousel.maxHeight,
            );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          if (_decodeWidth != width) {
            // 読み込み済みなら即座に結果が届くので、build の外で始める
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _resolveAspectRatios(width);
            });
          }
          return Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow,
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      // スワイプ中は前後の写真の高さの間をなめらかにつなぐ
                      final position = _controller.hasClients
                          ? _controller.page ?? _page.toDouble()
                          : _page.toDouble();
                      final from = position.floor().clamp(0, urls.length - 1);
                      final to = position.ceil().clamp(0, urls.length - 1);
                      final height = lerpDouble(
                        _heightOf(from, width, maxHeight),
                        _heightOf(to, width, maxHeight),
                        position - from,
                      )!;
                      return SizedBox(height: height, child: child);
                    },
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: urls.length,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (context, index) => _WholeImage(
                        image: _provider(urls[index], width),
                        blurredImage: ResizeImage(
                          _networkImage(urls[index]),
                          width: 48,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (urls.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Semantics(
                    label: '${urls.length}枚中${_page + 1}枚目',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < urls.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: i == _page ? 16 : 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: i == _page ? colors.accent : colors.fill,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 写真を切り抜かずに収め、余った左右（上下）はぼかした同じ写真で埋める。
class _WholeImage extends StatelessWidget {
  const _WholeImage({required this.image, required this.blurredImage});

  final ImageProvider image;

  /// 背景用の小さく読み込んだ写真。ぼかすので解像度は要らない。
  final ImageProvider blurredImage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: colors.card),
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Image(
            image: blurredImage,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        ColoredBox(color: colors.background.withValues(alpha: 0.35)),
        Image(
          image: image,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(child: CupertinoActivityIndicator()),
          errorBuilder: (context, error, stackTrace) =>
              Icon(CupertinoIcons.photo, size: 44, color: colors.textDisabled),
        ),
      ],
    );
  }
}
