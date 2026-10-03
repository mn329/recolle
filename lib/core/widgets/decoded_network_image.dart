import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';

/// 表示に必要な解像度だけデコードし、取得中はプレースホルダーを出すネットワーク画像。
///
/// [logicalHeight] を省略すると横幅いっぱいに元画像の縦横比で表示する。
class DecodedNetworkImage extends StatelessWidget {
  const DecodedNetworkImage({
    super.key,
    required this.url,
    required this.logicalWidth,
    this.logicalHeight,
    this.fit = BoxFit.cover,
    this.placeholderHeight = 200,
    this.errorBuilder,
    this.headers,
  });

  final String url;

  /// 取得時に付ける HTTP ヘッダー（非公開の画像に付ける認証など）。
  final Map<String, String>? headers;
  final double logicalWidth;
  final double? logicalHeight;
  final BoxFit fit;

  /// [logicalHeight] 省略時、読み込み中・URL 未設定時に確保する高さ。
  final double placeholderHeight;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final boxHeight = logicalHeight;
    if (url.isEmpty) {
      return SizedBox(
        height: boxHeight ?? placeholderHeight,
        child: ColoredBox(color: context.colors.card),
      );
    }

    // cacheWidth と cacheHeight を両方渡すと元の縦横比を無視してその寸法に引き伸ばされる。
    // 片方だけ渡して比率を保ち、表示サイズを決めやすい側の辺を基準にする
    // （cover は箱の長辺側、contain は箱の短辺側）。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    int toPx(double logical) => (logical * dpr).round().clamp(1, 1 << 15);
    final decodeByHeight = switch ((fit, boxHeight)) {
      (BoxFit.cover, final h?) => h > logicalWidth,
      (BoxFit.contain, final h?) => logicalWidth > h,
      _ => false,
    };

    return Image.network(
      url,
      headers: headers,
      fit: fit,
      width: logicalWidth,
      height: boxHeight,
      cacheWidth: decodeByHeight ? null : toPx(logicalWidth),
      cacheHeight: decodeByHeight ? toPx(boxHeight!) : null,
      gaplessPlayback: true,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return SizedBox(
          width: logicalWidth,
          height: boxHeight ?? placeholderHeight,
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
      errorBuilder: errorBuilder,
    );
  }
}
