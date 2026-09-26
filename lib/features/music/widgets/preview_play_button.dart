import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/app_toast.dart';
import 'package:recolle/features/music/providers/music_providers.dart';

/// 30 秒試聴の再生・一時停止ボタン。外周のリングで再生位置を示す。
class PreviewPlayButton extends ConsumerWidget {
  const PreviewPlayButton({
    super.key,
    required this.previewUrl,
    this.size = 40,
  });

  /// null なら試聴なし（ボタンを出さない）。
  final Uri? previewUrl;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = previewUrl;
    if (url == null) return const SizedBox.shrink();

    final player = ref.watch(previewPlayerProvider);
    final playing = player.isPlaying(url);
    final loading = player.isLoading(url);

    Future<void> toggle() async {
      HapticFeedback.selectionClick();
      try {
        await player.toggle(url);
      } catch (e) {
        AppToast.error(toUserFriendlyMessage(e));
      }
    }

    return Semantics(
      button: true,
      label: playing ? '試聴を一時停止' : '試聴を再生',
      child: CupertinoButton(
        padding: const EdgeInsets.all(4),
        minimumSize: Size.zero,
        onPressed: toggle,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (loading)
                CupertinoActivityIndicator(radius: size * 0.3)
              else ...[
                SizedBox.square(
                  dimension: size,
                  child: CircularProgressIndicator(
                    value: player.progressOf(url),
                    strokeWidth: size * 0.06,
                    color: context.colors.accent,
                    backgroundColor: context.colors.accent.withValues(
                      alpha: 0.18,
                    ),
                  ),
                ),
                Icon(
                  playing
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  size: size * 0.45,
                  color: context.colors.accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
