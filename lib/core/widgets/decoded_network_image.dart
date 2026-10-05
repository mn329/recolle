import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/widgets/managed_network_image.dart';

/// 画像の取得先（URL と、非公開の画像に付ける認証などのヘッダー）。
@immutable
class NetworkImageSource {
  const NetworkImageSource(this.url, {this.headers});

  final String url;
  final Map<String, String>? headers;
}

/// 表示に必要な解像度だけデコードし、取得中はくるくるを出すネットワーク画像。端末にも保存して使い回す。
///
/// [logicalHeight] を省略すると横幅いっぱいに元画像の縦横比で表示する。
///
/// 取得に失敗したら、[alternatives] を順に試す（小さな画像がない古い記録は、大きな画像に切り替わる）。
/// すべて失敗したら、少し待って 2 回まで取り直す。
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
    this.alternatives = const [],
  });

  final String url;

  /// 取得時に付ける HTTP ヘッダー（非公開の画像に付ける認証など）。
  final Map<String, String>? headers;

  /// [url] で取れなかったときに、順に試す取得先。
  final List<NetworkImageSource> alternatives;
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

  int _sourceIndex = 0;
  int _retries = 0;
  bool _recoveryScheduled = false;

  List<NetworkImageSource> get _sources => [
    NetworkImageSource(widget.url, headers: widget.headers),
    ...widget.alternatives,
  ];

  @override
  void didUpdateWidget(DecodedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _sourceIndex = 0;
      _retries = 0;
    }
  }

  /// 取得に失敗したときに、次の取得先に進むか、取り直す。build 中には setState できないので遅らせる。
  void _scheduleRecovery() {
    if (_recoveryScheduled) return;
    final sources = _sources;
    final hasNext = _sourceIndex + 1 < sources.length;
    final canRetry = !hasNext && _retries < _maxRetries;
    if (!hasNext && !canRetry) return;
    _recoveryScheduled = true;
    Future<void>.delayed(hasNext ? Duration.zero : _retryDelay, () {
      _recoveryScheduled = false;
      if (!mounted) return;
      setState(() {
        if (hasNext) {
          _sourceIndex++;
        } else {
          _retries++;
          // 小さな画像がない（古い記録）ことが多いので、取り直しは大きな画像から
          _sourceIndex = sources.length > 1 ? 1 : 0;
        }
      });
    });
  }

  Widget _placeholder(BuildContext context, {required bool loading}) {
    return SizedBox(
      width: widget.logicalWidth,
      height: widget.logicalHeight ?? widget.placeholderHeight,
      child: ColoredBox(
        color: context.colors.card,
        child: loading
            ? const Center(child: CupertinoActivityIndicator())
            : null,
      ),
    );
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

    final sources = _sources;
    final source = sources[_sourceIndex.clamp(0, sources.length - 1)];
    final provider = ResizeImage.resizeIfNeeded(
      decodeByHeight ? null : toPx(logicalWidth),
      decodeByHeight ? toPx(boxHeight!) : null,
      ManagedNetworkImage(source.url, headers: source.headers),
    );
    return Image(
      key: ValueKey((source.url, _retries)),
      image: provider,
      fit: widget.fit,
      width: logicalWidth,
      height: boxHeight,
      gaplessPlayback: true,
      // 最初の 1 コマが出るまで（ダウンロード・デコード中）は、くるくるを出す
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return _placeholder(context, loading: true);
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint(
          'Image load failed (${source.url}, source $_sourceIndex, retry $_retries): $error',
        );
        _scheduleRecovery();
        final builder = widget.errorBuilder;
        if (builder != null) return builder(context, error, stackTrace);
        return _placeholder(context, loading: false);
      },
    );
  }
}
