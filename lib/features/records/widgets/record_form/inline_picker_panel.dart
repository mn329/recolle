import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';

/// 行の下にホイールを開く行の開閉状態。
///
/// 開いている間は行がフォーカスを持ち、別の入力欄や別のホイールにフォーカスが移ったら閉じる。
/// 行の [build] 全体を `Focus(focusNode: pickerFocusNode, ...)` で包んで使う。
mixin InlinePickerExpansion<T extends StatefulWidget> on State<T> {
  final pickerFocusNode = FocusNode(
    debugLabel: 'InlinePicker',
    skipTraversal: true,
  );
  bool expanded = false;

  @override
  void initState() {
    super.initState();
    pickerFocusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    pickerFocusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!pickerFocusNode.hasFocus && expanded) {
      setState(() => expanded = false);
    }
  }

  /// 開くときはフォーカスを取り、入力中の欄のキーボードも閉じる。
  void setExpanded(bool value) {
    if (value) {
      pickerFocusNode.requestFocus();
    } else if (pickerFocusNode.hasFocus) {
      pickerFocusNode.unfocus();
    }
    setState(() => expanded = value);
  }
}

/// 行の下に開くホイールと、閉じるための「完了」ボタン。
///
/// ホイールの値は回したそばから反映されるが、閉じ方が行の再タップだけだと分かりにくいため、
/// 確定の操作として「完了」を置く。
class InlinePickerPanel extends StatelessWidget {
  const InlinePickerPanel({
    super.key,
    required this.picker,
    required this.onDone,
  });

  static const double pickerHeight = 200;

  final Widget picker;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: pickerHeight, child: picker),
        Align(
          alignment: Alignment.centerRight,
          child: CupertinoButton(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            minimumSize: const Size(44, 44),
            onPressed: onDone,
            child: Text(
              '完了',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.colors.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
