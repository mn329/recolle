import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/widgets/app_toast.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/share/record_share_card.dart';
import 'package:share_plus/share_plus.dart';

/// 記録をシェア画像にして、iOS の共有シート（ストーリーズ・写真に保存など）に渡すシート。
Future<void> showShareRecordSheet(BuildContext context, Record record) {
  return showCupertinoSheet<void>(
    context: context,
    builder: (_) => _ShareRecordSheet(record: record),
  );
}

class _ShareRecordSheet extends HookWidget {
  const _ShareRecordSheet({required this.record});

  final Record record;

  /// 3 倍で書き出すと幅 1080px になる。
  static const double _pixelRatio = 3;

  @override
  Widget build(BuildContext context) {
    final style = useState(ShareCardStyle.ticket);
    final theme = useState(ShareCardTheme.gold);
    final boundaryKey = useMemoized(GlobalKey.new);
    final isSharing = useState(false);

    Future<void> share() async {
      if (isSharing.value) return;
      isSharing.value = true;
      // 共有シートを出す位置（iPad で必須）。ボタンのある画面下部を指定する
      final size = MediaQuery.sizeOf(context);
      final origin = Rect.fromLTWH(0, size.height - 100, size.width, 100);
      try {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: _pixelRatio);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (bytes == null) throw StateError('画像を書き出せませんでした');

        final dir = await getTemporaryDirectory();
        final file = File(
          p.join(
            dir.path,
            'recolle_${record.id}_${style.value.name}_${theme.value.name}.png',
          ),
        );
        await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'image/png')],
            sharePositionOrigin: origin,
          ),
        );
      } catch (e) {
        debugPrint('Share image failed: $e');
        AppToast.error('シェア画像を作れませんでした。もう一度お試しください。');
      } finally {
        if (context.mounted) isSharing.value = false;
      }
    }

    return CupertinoPageScaffold(
      backgroundColor: context.colors.background,
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        backgroundColor: context.colors.background,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 44),
          onPressed: () => Navigator.pop(context),
          child: Text(
            '閉じる',
            style: TextStyle(color: context.colors.accent, fontSize: 17),
          ),
        ),
        middle: const Text('シェア画像'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: IosSegmentedControl<ShareCardStyle>(
                value: style.value,
                segments: {for (final s in ShareCardStyle.values) s: s.label},
                onChanged: (s) => style.value = s,
              ),
            ),
            _ThemePicker(
              selected: theme.value,
              onSelected: (t) => theme.value = t,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: boundaryKey,
                      child: RecordShareCard(
                        record: record,
                        style: style.value,
                        theme: theme.value,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: isSharing.value ? null : share,
                  child: isSharing.value
                      ? const CupertinoActivityIndicator()
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.square_arrow_up,
                              color: context.colors.onAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '共有・保存',
                              style: TextStyle(
                                color: context.colors.onAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// シェア画像の差し色を選ぶ丸い見本の列。
class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.selected, required this.onSelected});

  final ShareCardTheme selected;
  final ValueChanged<ShareCardTheme> onSelected;

  static const double _swatch = 30;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        itemCount: ShareCardTheme.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final t = ShareCardTheme.values[index];
          final isSelected = t == selected;
          return Semantics(
            button: true,
            selected: isSelected,
            label: '${t.label}の色',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => onSelected(t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _swatch + 8,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? context.colors.textPrimary
                        : const Color(0x00000000),
                    width: 2,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.onDark,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
