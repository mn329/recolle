import 'package:flutter/material.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/features/music/music_links.dart';
import 'package:url_launcher/url_launcher.dart';

/// Apple Music / Spotify / YouTube Music を開くボタン列。
class StreamingLinks extends StatelessWidget {
  const StreamingLinks({super.key, required this.query, this.appleMusicUrl});

  /// Spotify・YouTube Music（と Apple Music の直リンクがないとき）の検索語。
  final String query;
  final Uri? appleMusicUrl;

  static const _brandColors = {
    StreamingService.appleMusic: Color(0xFFFA2D48),
    StreamingService.spotify: Color(0xFF1DB954),
    StreamingService.youtubeMusic: Color(0xFFFF0033),
  };

  static const _icons = {
    StreamingService.appleMusic: Icons.music_note_rounded,
    StreamingService.spotify: Icons.graphic_eq_rounded,
    StreamingService.youtubeMusic: Icons.play_circle_fill_rounded,
  };

  Future<void> _open(BuildContext context, StreamingService service) async {
    final uri = service.link(
      query: query,
      directUrl: service == StreamingService.appleMusic ? appleMusicUrl : null,
    );
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('launchUrl failed for $uri: $e');
    }
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text('${service.label} を開けませんでした')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final service in StreamingService.values) ...[
          if (service != StreamingService.values.first)
            const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => _open(context, service),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                backgroundColor: AppColors.surfaceLight,
                side: BorderSide(
                  color: _brandColors[service]!.withValues(alpha: 0.6),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_icons[service], color: _brandColors[service], size: 22),
                  const SizedBox(height: 4),
                  Text(
                    service.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
