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
