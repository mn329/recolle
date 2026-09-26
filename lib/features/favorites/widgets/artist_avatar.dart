import 'package:flutter/material.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/widgets/decoded_network_image.dart';

/// アーティストのアートワーク。画像がない・読めないときは頭文字を表示する。
class ArtistAvatar extends StatelessWidget {
  const ArtistAvatar({
    super.key,
    required this.name,
    required this.size,
    this.artworkUrl,
    this.borderRadius,
  });

  final String name;
  final String? artworkUrl;
  final double size;

  /// null なら円形。
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final url = artworkUrl;
    final fallback = _InitialFallback(name: name, size: size);
    final image = url == null || url.isEmpty
        ? fallback
        : DecodedNetworkImage(
            url: url,
            logicalWidth: size,
            logicalHeight: size,
            errorBuilder: (context, error, stackTrace) => fallback,
          );

    return SizedBox.square(
      dimension: size,
      child: borderRadius == null
          ? ClipOval(child: image)
          : ClipRRect(borderRadius: borderRadius!, child: image),
    );
  }
}

/// 画面間で [ArtistAvatar] を Hero 遷移させる。
///
/// Hero の飛行中は親の ClipRRect の外で描画されるため、角丸は親に頼らず
/// アバター自身に持たせ、遷移元と遷移先の角丸を補間する（着地時に角丸が遅れて付かないように）。
class ArtistArtworkHero extends StatelessWidget {
  const ArtistArtworkHero({
    super.key,
    required this.tag,
    required this.name,
    required this.size,
    required this.borderRadius,
    this.artworkUrl,
  });

  final Object tag;
  final String name;
  final String? artworkUrl;
  final double size;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      flightShuttleBuilder: (context, animation, direction, fromCtx, toCtx) {
        BorderRadius radiusOf(BuildContext heroContext) =>
            ((heroContext.widget as Hero).child as ArtistAvatar).borderRadius ??
            BorderRadius.zero;
        final from = radiusOf(fromCtx);
        final to = radiusOf(toCtx);
        // push は 0→1、pop は 1→0 で進むので、t=0 側が常に「下の画面」になるよう揃える
        final (lower, upper) = direction == HeroFlightDirection.push
            ? (from, to)
            : (to, from);
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) => ArtistAvatar(
              name: name,
              artworkUrl: artworkUrl,
              size: constraints.biggest.longestSide,
              borderRadius: BorderRadius.lerp(lower, upper, animation.value),
            ),
          ),
        );
      },
      child: ArtistAvatar(
        name: name,
        artworkUrl: artworkUrl,
        size: size,
        borderRadius: borderRadius,
      ),
    );
  }
}

class _InitialFallback extends StatelessWidget {
  const _InitialFallback({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.gold.withValues(alpha: 0.35),
            AppColors.surfaceLight,
          ],
        ),
      ),
      child: Center(
        child: Text(
          initial.toUpperCase(),
          style: AppFonts.displayStyle(
            fontSize: size * 0.42,
            color: AppColors.gold,
          ),
        ),
      ),
    );
  }
}
