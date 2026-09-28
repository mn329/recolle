import 'package:flutter/cupertino.dart';
// Apple のロゴは CupertinoIcons に無いため Material のアイコンを使う
import 'package:flutter/material.dart' show Icons;
import 'package:recolle/features/account/services/social_credential.dart';

/// Apple / Google で続行するボタン群。使えるものだけ出す（[availableSocialProviders]）。
class SocialSignInButtons extends StatelessWidget {
  const SocialSignInButtons({
    super.key,
    required this.isBusy,
    required this.onPressed,
    this.hiddenProviders = const {},
  });

  final bool isBusy;
  final void Function(SocialProvider provider) onPressed;

  /// 連携済みなどで出さない provider。
  final Set<SocialProvider> hiddenProviders;

  @override
  Widget build(BuildContext context) {
    final providers = availableSocialProviders
        .where((p) => !hiddenProviders.contains(p))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, provider) in providers.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          _SocialButton(
            provider: provider,
            onPressed: isBusy ? null : () => onPressed(provider),
          ),
        ],
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.provider, required this.onPressed});

  final SocialProvider provider;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = switch (provider) {
      SocialProvider.apple => 'Apple で続ける',
      SocialProvider.google => 'Google で続ける',
    };

    return CupertinoButton(
      color: CupertinoColors.white,
      disabledColor: CupertinoColors.white.withAlpha(90),
      borderRadius: BorderRadius.circular(12),
      minimumSize: const Size.fromHeight(50),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            child: Center(child: _ProviderMark(provider: provider)),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: CupertinoColors.black,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderMark extends StatelessWidget {
  const _ProviderMark({required this.provider});

  final SocialProvider provider;

  @override
  Widget build(BuildContext context) {
    return switch (provider) {
      SocialProvider.apple => const Icon(
        Icons.apple,
        size: 22,
        color: CupertinoColors.black,
      ),
      SocialProvider.google => const _GoogleMark(),
    };
  }
}

/// 設定行の先頭に置く、白い角丸四角に provider のロゴ。
class SocialProviderIcon extends StatelessWidget {
  const SocialProviderIcon({super.key, required this.provider});

  final SocialProvider provider;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(7),
      ),
      child: SizedBox.square(
        dimension: 30,
        child: Center(child: _ProviderMark(provider: provider)),
      ),
    );
  }
}

/// Google の 4 色「G」マーク（画像アセットを増やさずに描画する）。
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 20,
      child: CustomPaint(painter: _GoogleMarkPainter()),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();

  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final rect =
        Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    Paint arc(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    const deg = 3.1415926535 / 180;
    canvas.drawArc(rect, -40 * deg, -95 * deg, false, arc(_red));
    canvas.drawArc(rect, -135 * deg, -90 * deg, false, arc(_yellow));
    canvas.drawArc(rect, -225 * deg, -100 * deg, false, arc(_green));
    canvas.drawArc(rect, -325 * deg, -35 * deg, false, arc(_blue));

    final center = size.center(Offset.zero);
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx,
        center.dy - stroke / 2,
        size.width / 2 - stroke / 2 + stroke / 2,
        stroke,
      ),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
