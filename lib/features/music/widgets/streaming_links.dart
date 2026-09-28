import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/widgets/app_toast.dart';
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
    StreamingService.appleMusic: CupertinoIcons.music_note_2,
    StreamingService.spotify: CupertinoIcons.waveform,
    StreamingService.youtubeMusic: CupertinoIcons.play_circle_fill,
  };

  Future<void> _open(StreamingService service) async {
    final uri = service.link(
      query: query,
      directUrl: service == StreamingService.appleMusic ? appleMusicUrl : null,
    );
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('launchUrl failed for $uri: $e');
    }
    if (!opened) AppToast.error('${service.label} を開けませんでした');
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final service in StreamingService.values) ...[
          if (service != StreamingService.values.first)
            const SizedBox(width: 8),
          Expanded(
            child: CupertinoButton(
              color: context.colors.card,
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              minimumSize: Size.zero,
              onPressed: () => _open(service),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_icons[service], color: _brandColors[service], size: 22),
                  const SizedBox(height: 4),
                  Text(
                    service.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.textPrimary,
                    ),
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
