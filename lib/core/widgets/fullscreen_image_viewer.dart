import 'package:flutter/material.dart';
import 'package:recolle/core/theme/app_colors.dart';

/// 画像を全画面で表示し、ピンチ・ダブルタップで拡大できるビューア。
class FullscreenImageViewer extends StatefulWidget {
  const FullscreenImageViewer({
    super.key,
    required this.url,
    required this.heroTag,
  });

  final String url;
  final Object heroTag;

  static Future<void> open(
    BuildContext context, {
    required String url,
    required Object heroTag,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) =>
            FullscreenImageViewer(url: url, heroTag: heroTag),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer>
    with SingleTickerProviderStateMixin {
  static const double _doubleTapScale = 2.5;

  final _transformController = TransformationController();
  late final AnimationController _zoomAnimation;
  Animation<Matrix4>? _zoomTween;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _zoomAnimation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final tween = _zoomTween;
          if (tween != null) _transformController.value = tween.value;
        });
  }

  @override
  void dispose() {
    _zoomAnimation.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final isZoomed = _transformController.value.getMaxScaleOnAxis() > 1.01;
    final Matrix4 end;
    if (isZoomed) {
      end = Matrix4.identity();
    } else {
      final focal = _doubleTapDetails?.localPosition ?? Offset.zero;
      end = Matrix4.identity()
        ..translateByDouble(
          -focal.dx * (_doubleTapScale - 1),
          -focal.dy * (_doubleTapScale - 1),
          0,
          1,
        )
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
    }
    _zoomTween = Matrix4Tween(
      begin: _transformController.value,
      end: end,
    ).animate(CurvedAnimation(parent: _zoomAnimation, curve: Curves.easeOut));
    _zoomAnimation.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTapDown: (d) => _doubleTapDetails = d,
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Hero(
                    tag: widget.heroTag,
                    child: Image.network(
                      widget.url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image,
                        size: 50,
                        color: AppColors.textDisabled,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: '閉じる',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
