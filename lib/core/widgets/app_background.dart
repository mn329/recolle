import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:recolle/core/theme/app_colors.dart';

/// 画面の地。上から差すステージ照明のようなアクセント色の光と、下から打ち上げるレーザー、
/// 紙のようなごく薄い粒子を重ねる。
///
/// 各画面の `Scaffold` を包み、`Scaffold` 自体は透明にする。画面ごとに不透明な地を持たせるのは、
/// 遷移やスワイプで戻る途中に下の画面が透けないようにするため。
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          // 画面の中身が再描画されても、地は描き直さない
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _BackdropPainter(
                colors: context.colors,
                pixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({required this.colors, required this.pixelRatio});

  final AppPalette colors;
  final double pixelRatio;

  /// 粒子の密度（1 論理ピクセル四方あたりの点の数）。
  static const _grainDensity = 0.05;

  /// 画面下端からタブバーが覆うおおよその高さ。
  static const _tabBarReserve = 110.0;

  /// 描き上がった地の画像。ぼかしと大量の粒子を画面を開くたびに描き直すと遷移が重くなるので、
  /// 同じ大きさ・配色の画面では使い回す。テーマの切り替え途中の配色が溜まらないよう数を絞る。
  static final _cache = <(Size, double, Color, Color, Color), ui.Image>{};
  static const _cacheLimit = 4;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final key = (
      size,
      pixelRatio,
      colors.background,
      colors.accent,
      colors.accentLight,
    );
    final image = _cache.remove(key) ?? _rasterize(size);
    // 最近使ったものを後ろへ回し、あふれたら最も古いものから捨てる
    _cache[key] = image;
    if (_cache.length > _cacheLimit) _cache.remove(_cache.keys.first);

    canvas
      ..save()
      ..scale(1 / pixelRatio)
      ..drawImage(image, Offset.zero, Paint())
      ..restore();
  }

  ui.Image _rasterize(Size size) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    _paintBackdrop(canvas, size);
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(
        (size.width * pixelRatio).ceil(),
        (size.height * pixelRatio).ceil(),
      );
    } finally {
      picture.dispose();
    }
  }

  void _paintBackdrop(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // レーザーは画面外まで伸ばして描くので、画面の枠で切り抜く
    canvas
      ..clipRect(rect)
      ..drawRect(rect, Paint()..color = colors.background);

    // 画面の上端の少し外に光源を置き、下へ向かって薄れる光にする
    final dark = colors.isDark;
    final glow = colors.accent;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -1.1),
          radius: 1.7,
          colors: [
            glow.withValues(alpha: dark ? 0.18 : 0.16),
            glow.withValues(alpha: dark ? 0.06 : 0.05),
            glow.withValues(alpha: dark ? 0.02 : 0.015),
            glow.withValues(alpha: 0),
          ],
          stops: const [0, 0.35, 0.7, 1],
        ).createShader(rect),
    );

    _paintLasers(canvas, size, dark);
    _paintGrain(canvas, size, dark);
  }

  /// 画面下の左右から上へ伸び、交差するレーザー光。
  void _paintLasers(Canvas canvas, Size size, bool dark) {
    // タブバーに隠れない高さから打ち上げる
    final bottom = size.height - _tabBarReserve;
    if (bottom <= 0) return;
    // 向きは真上を 0 度・右を正とする
    const angles = [18.0, 30.0, 44.0];
    final fade = ui.Gradient.linear(Offset(0, bottom), Offset.zero, [
      colors.accent.withValues(alpha: dark ? 0.18 : 0.22),
      colors.accent.withValues(alpha: 0),
    ]);
    final halo = Paint()
      ..shader = fade
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final core = Paint()
      ..shader = fade
      ..strokeWidth = 1;
    final reach = size.height * 1.2;
    for (final (originX, side) in [(-20.0, 1.0), (size.width + 20, -1.0)]) {
      final origin = Offset(originX, bottom);
      for (final angle in angles) {
        final rad = side * angle * pi / 180;
        final end = origin + Offset(sin(rad), -cos(rad)) * reach;
        canvas
          ..drawLine(origin, end, halo)
          ..drawLine(origin, end, core);
      }
    }
  }

  void _paintGrain(Canvas canvas, Size size, bool dark) {
    // 毎回同じ模様になるよう種を固定する（描き直しても粒子がちらつかない）
    final random = Random(7);
    final count = (size.width * size.height * _grainDensity).round();
    Float32List points(int n) {
      final list = Float32List(n * 2);
      for (var i = 0; i < list.length; i += 2) {
        list[i] = random.nextDouble() * size.width;
        list[i + 1] = random.nextDouble() * size.height;
      }
      return list;
    }

    // 1 物理ピクセル強の点にして、拡大しても荒く見えないようにする
    final dotSize = 1.5 / pixelRatio;
    final light = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: dark ? 0.045 : 0.35)
      ..strokeWidth = dotSize
      ..strokeCap = StrokeCap.round;
    final shade = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: dark ? 0.35 : 0.045)
      ..strokeWidth = dotSize
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawRawPoints(ui.PointMode.points, points(count ~/ 2), light)
      ..drawRawPoints(ui.PointMode.points, points(count ~/ 2), shade);
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.pixelRatio != pixelRatio;
}
