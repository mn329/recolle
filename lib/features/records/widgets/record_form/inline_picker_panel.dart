import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';

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
