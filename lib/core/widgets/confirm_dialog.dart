import 'package:flutter/cupertino.dart';

/// iOS のアラートで確認をとる。OK なら true。
///
/// [isDestructive] は削除・破棄など取り消せない操作に使い、OK ボタンを赤字にする。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String okText = 'OK',
  String cancelText = 'キャンセル',
  bool isDestructive = false,
}) async {
  final res = await showCupertinoDialog<bool>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(message),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelText),
        ),
        CupertinoDialogAction(
          isDefaultAction: !isDestructive,
          isDestructiveAction: isDestructive,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(okText),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// [showActionSheet] の選択肢。
class SheetAction<T> {
  const SheetAction({
    required this.label,
    required this.value,
    this.isDestructive = false,
  });

  final String label;
  final T value;
  final bool isDestructive;
}

/// 画面下からせり上がる iOS のアクションシート。キャンセル・枠外タップで null。
Future<T?> showActionSheet<T>(
  BuildContext context, {
  required List<SheetAction<T>> actions,
  String? title,
  String? message,
  String cancelText = 'キャンセル',
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: title == null ? null : Text(title),
      message: message == null ? null : Text(message),
      actions: [
        for (final action in actions)
          CupertinoActionSheetAction(
            isDestructiveAction: action.isDestructive,
            onPressed: () => Navigator.of(context).pop(action.value),
            child: Text(action.label),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.of(context).pop(),
        child: Text(cancelText),
      ),
    ),
  );
}
