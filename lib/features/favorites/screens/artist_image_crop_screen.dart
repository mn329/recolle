import 'dart:io';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/app_toast.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/artist_image_output.dart';

/// 切り抜いた画像を、アップロードするファイルに仕上げる。
typedef ArtistImageFinisher = Future<File> Function(Uint8List cropped);

/// 選んだ画像から、正方形に切り抜く範囲を決める画面。
///
/// 「完了」で切り抜いた画像のファイルを返して閉じる。キャンセルは null。
class ArtistImageCropScreen extends StatefulWidget {
  const ArtistImageCropScreen({
    super.key,
    required this.file,
    this.finisher = saveArtistImageAsJpeg,
  });

  final File file;
  final ArtistImageFinisher finisher;

  @override
  State<ArtistImageCropScreen> createState() => _ArtistImageCropScreenState();
}

class _ArtistImageCropScreenState extends State<ArtistImageCropScreen> {
  final _controller = CropController();
  Uint8List? _bytes;
  bool _loadFailed = false;
  bool _ready = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.file.readAsBytes();
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (e) {
      debugPrint('ArtistImageCropScreen: 画像を読み込めませんでした: $e');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  void _onStatusChanged(CropStatus status) {
    // 画像の準備中・切り抜き中は完了を押せない
    final ready = status == CropStatus.ready;
    if (_ready != ready) setState(() => _ready = ready);
  }

  void _onDone() {
    setState(() => _busy = true);
    _controller.crop();
  }

  Future<void> _onCropped(CropResult result) async {
    try {
      switch (result) {
        case CropSuccess(:final croppedImage):
          final file = await widget.finisher(croppedImage);
          if (!mounted) return;
          Navigator.of(context).pop(file);
        case CropFailure(:final cause):
          throw cause;
      }
    } catch (e) {
      debugPrint('ArtistImageCropScreen: 切り抜きに失敗しました: $e');
      AppToast.error(toUserFriendlyMessage(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bytes = _bytes;
    final Widget body;
    if (_loadFailed) {
      body = Center(
        child: Text(
          '画像を読み込めませんでした',
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    } else if (bytes == null) {
      body = const Center(child: CupertinoActivityIndicator(radius: 14));
    } else {
      body = Crop(
        image: bytes,
        controller: _controller,
        onCropped: _onCropped,
        onStatusChanged: _onStatusChanged,
        aspectRatio: 1,
        // 枠は動かさず、画像を動かして拡大・縮小して決める（プロフィール画像の編集と同じ操作）
        interactive: true,
        fixCropRect: true,
        baseColor: colors.background,
        maskColor: Colors.black.withValues(alpha: 0.6),
        radius: 12,
        // 枠は固定で動かせないので、四隅の丸い操作点は要らない（既定では描かれてしまう）
        cornerDotBuilder: (size, edgeAlignment) => const SizedBox.shrink(),
        progressIndicator: const CupertinoActivityIndicator(radius: 14),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                NavBarTextButton(
                  label: 'キャンセル',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
                NavBarTextButton(
                  label: '完了',
                  isBold: true,
                  onPressed: _ready && !_busy ? _onDone : null,
                ),
              ],
            ),
            Expanded(child: body),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Text(
                'ドラッグで位置を、ピンチで大きさを調整できます',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
