import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';

/// 表示に必要な解像度だけデコードし、取得中はプレースホルダーを出すネットワーク画像。
///
/// [logicalHeight] を省略すると横幅いっぱいに元画像の縦横比で表示する。
///
/// 取得に失敗したら、少し待って 2 回まで取り直す。それでも失敗し、[fallbackUrl] があれば、
/// ヘッダーなしでその URL を取る（認証つきの窓口で取れないときの保険）。
class DecodedNetworkImage extends StatefulWidget {
  const DecodedNetworkImage({
    super.key,
    required this.url,
    required this.logicalWidth,
    this.logicalHeight,
    this.fit = BoxFit.cover,
    this.placeholderHeight = 200,
    this.errorBuilder,
    this.headers,
    this.fallbackUrl,
  });

  final String url;

  /// 取得時に付ける HTTP ヘッダー（非公開の画像に付ける認証など）。
  final Map<String, String>? headers;

  /// [url] で取れなかったときに、ヘッダーなしで取り直す URL。
  final String? fallbackUrl;
  final double logicalWidth;
  final double? logicalHeight;
  final BoxFit fit;

  /// [logicalHeight] 省略時、読み込み中・URL 未設定時に確保する高さ。
  final double placeholderHeight;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<DecodedNetworkImage> createState() => _DecodedNetworkImageState();
}

class _DecodedNetworkImageState extends State<DecodedNetworkImage> {
  static const _maxRetries = 2;
  static const _retryDelay = Duration(milliseconds: 1500);

  int _attempt = 0;
  bool _useFallback = false;
  bool _recoveryScheduled = false;

  @override
  void didUpdateWidget(DecodedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _attempt = 0;
      _useFallback = false;
    }
  }

  /// 取得に失敗したときに、取り直すか、保険の URL に切り替える。build 中には setState できないので遅らせる。
  void _scheduleRecovery() {
    if (_recoveryScheduled) return;
    final canRetry = !_useFallback && _attempt < _maxRetries;
    final canFallback =
        !_useFallback && widget.fallbackUrl != null && !canRetry;
    if (!canRetry && !canFallback) return;
    _recoveryScheduled = true;
    Future<void>.delayed(canRetry ? _retryDelay : Duration.zero, () {
      _recoveryScheduled = false;
      if (!mounted) return;
      setState(() {
        if (canRetry) {
          _attempt++;
        } else {
          _useFallback = true;
          _attempt = 0;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final boxHeight = widget.logicalHeight;
    final logicalWidth = widget.logicalWidth;
    if (widget.url.isEmpty) {
      return SizedBox(
        height: boxHeight ?? widget.placeholderHeight,
        child: ColoredBox(color: context.colors.card),
      );
    }

    // cacheWidth と cacheHeight を両方渡すと元の縦横比を無視してその寸法に引き伸ばされる。
    // 片方だけ渡して比率を保ち、表示サイズを決めやすい側の辺を基準にする
    // （cover は箱の長辺側、contain は箱の短辺側）。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    int toPx(double logical) => (logical * dpr).round().clamp(1, 1 << 15);
    final decodeByHeight = switch ((widget.fit, boxHeight)) {
      (BoxFit.cover, final h?) => h > logicalWidth,
      (BoxFit.contain, final h?) => logicalWidth > h,
      _ => false,
    };

    final url = _useFallback ? widget.fallbackUrl! : widget.url;
    return Image.network(
      url,
      key: ValueKey((url, _attempt)),
      headers: _useFallback ? null : widget.headers,
      fit: widget.fit,
      width: logicalWidth,
      height: boxHeight,
      cacheWidth: decodeByHeight ? null : toPx(logicalWidth),
      cacheHeight: decodeByHeight ? toPx(boxHeight!) : null,
      gaplessPlayback: true,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return SizedBox(
          width: logicalWidth,
          height: boxHeight ?? widget.placeholderHeight,
          child: ColoredBox(
            color: context.colors.card,
            child: Center(
              child: loadingProgress.expectedTotalBytes != null
                  ? CupertinoActivityIndicator.partiallyRevealed(
                      progress:
                          loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!,
                    )
                  : const CupertinoActivityIndicator(),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Image load failed ($url, attempt $_attempt): $error');
        _scheduleRecovery();
        final builder = widget.errorBuilder;
        return builder == null
            ? SizedBox(
                width: logicalWidth,
                height: boxHeight ?? widget.placeholderHeight,
                child: ColoredBox(color: context.colors.card),
              )
            : builder(context, error, stackTrace);
      },
    );
  }
}
