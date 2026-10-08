import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';

/// 入力行の左端に置く項目のアイコン。
class FormRowIcon extends StatelessWidget {
  const FormRowIcon(this.icon, {super.key, this.active = false});

  static const double width = 22;

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    return SizedBox(
      width: width,
      child: Icon(
        icon,
        size: 19,
        color: active ? accent : accent.withValues(alpha: 0.7),
      ),
    );
  }
}

/// チケットの半券と同じ、等幅の英字で書いた小さな項目名。
class FormFieldLabel extends StatelessWidget {
  const FormFieldLabel(this.text, {super.key, this.required = false});

  final String text;

  /// 必須の項目なら、見出しの隣に「＊」を付ける。
  final bool required;

  @override
  Widget build(BuildContext context) {
    final style = AppFonts.monoStyle(
      fontSize: 10.5,
      color: context.colors.accent,
    ).copyWith(letterSpacing: 1.2);
    if (!required) return Text(text, style: style);
    return Text.rich(
      TextSpan(
        text: text,
        children: [
          TextSpan(
            text: ' ＊',
            style: style.copyWith(color: context.colors.destructive),
          ),
        ],
      ),
      style: style,
    );
  }
}

/// 日付・時刻など、タップで開く行の左側（アイコンと項目名）。
class FormRowTitle extends StatelessWidget {
  const FormRowTitle({
    super.key,
    required this.label,
    this.icon,
    this.enLabel,
    this.active = false,
  });

  final String label;
  final IconData? icon;
  final String? enLabel;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      label,
      style: TextStyle(fontSize: 16, color: context.colors.textPrimary),
    );
    return Row(
      children: [
        if (icon != null) ...[
          FormRowIcon(icon!, active: active),
          const SizedBox(width: 12),
        ],
        Flexible(
          child: enLabel == null
              ? title
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FormFieldLabel(enLabel!),
                    const SizedBox(height: 2),
                    title,
                  ],
                ),
        ),
      ],
    );
  }
}

/// 入力中・操作中の行を、左端のアクセントの線と淡い背景で示す。
class FormRowHighlight extends StatelessWidget {
  const FormRowHighlight({
    super.key,
    required this.active,
    required this.child,
  });

  static const double barWidth = 3;

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: active ? accent.withValues(alpha: 0.07) : null,
        border: Border(
          left: BorderSide(
            color: active ? accent : const Color(0x00000000),
            width: barWidth,
          ),
        ),
      ),
      child: child,
    );
  }
}
