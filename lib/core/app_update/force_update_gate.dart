import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/app_update/force_update_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// 最低バージョンより古いアプリを、全画面で止めて App Store へ誘導する。
///
/// [MaterialApp.builder] で全画面の一番外側に置く。止めているあいだは下の画面に操作・読み上げ・キーボード入力が届かない。
class ForceUpdateGate extends HookConsumerWidget {
  const ForceUpdateGate({super.key, required this.child});

  final Widget child;

  static final Uri appStoreUrl = Uri.parse(
    'https://apps.apple.com/app/id6762868760',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateRequired = ref.watch(forceUpdateProvider);

    // App Store から戻ってきたときなどに確認し直す
    useOnAppLifecycleStateChange((_, state) {
      if (state == AppLifecycleState.resumed) {
        ref.read(forceUpdateProvider.notifier).check();
      }
    });

    return Stack(
      fit: StackFit.expand,
      children: [
        // 入力中に止めたときもキーボードを閉じ、見えない入力欄に文字が入らないようにする
        ExcludeFocus(
          excluding: updateRequired,
          child: ExcludeSemantics(excluding: updateRequired, child: child),
        ),
        if (updateRequired) const _ForceUpdateScreen(),
      ],
    );
  }
}

class _ForceUpdateScreen extends StatelessWidget {
  const _ForceUpdateScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      // 画面全体が 1 つのボタンとして読み上げられないよう、見出し・本文・ボタンを分ける
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'アップデートが必要です',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'このバージョンはご利用いただけなくなりました。App Store から最新版にアップデートしてください。',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                CupertinoButton.filled(
                  onPressed: _openAppStore,
                  child: const Text('App Store を開く'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openAppStore() async {
  try {
    await launchUrl(
      ForceUpdateGate.appStoreUrl,
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    debugPrint('launchUrl failed for ${ForceUpdateGate.appStoreUrl}: $e');
  }
}
