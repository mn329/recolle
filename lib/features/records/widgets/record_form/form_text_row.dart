import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:recolle/core/theme/app_colors.dart';

/// [FormCard] の中に置く、枠のない iOS の入力行。見出しの代わりにプレースホルダーで項目を示す。
class FormTextRow extends StatelessWidget {
  const FormTextRow({
    super.key,
    required this.controller,
    required this.placeholder,
    this.focusNode,
    this.onChanged,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.textInputAction,
    this.keyboardType,
    this.inputFormatters,
    this.suffix,
    this.scrollPadding = const EdgeInsets.all(20),
  });

  final TextEditingController controller;
  final String placeholder;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  /// 入力欄の右端に添える単位など（「円」）。
  final String? suffix;

  /// キーボード表示時に ensureVisible が十分スクロールするよう拡げる。
  final EdgeInsets scrollPadding;

  /// 常に「0/100」が並ぶと騒がしいので、上限が近づいてから出す。
  static const double _counterVisibleRatio = 0.8;

  @override
  Widget build(BuildContext context) {
    final multiline = maxLines > 1;
    final limit = maxLength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoTextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          placeholder: placeholder,
          maxLines: maxLines,
          minLines: minLines ?? (multiline ? 3 : null),
          maxLength: maxLength,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          suffix: suffix == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    suffix!,
                    style: TextStyle(
                      fontSize: 16,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
          textInputAction:
              textInputAction ??
              (multiline ? TextInputAction.newline : TextInputAction.next),
          scrollPadding: scrollPadding,
          clearButtonMode: multiline
              ? OverlayVisibilityMode.never
              : OverlayVisibilityMode.editing,
          decoration: null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          cursorColor: context.colors.accent,
          style: TextStyle(
            fontSize: 16,
            height: 1.4,
            color: context.colors.textPrimary,
          ),
          placeholderStyle: TextStyle(
            fontSize: 16,
            height: 1.4,
            color: context.colors.textDisabled,
          ),
        ),
        if (limit != null)
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, value, _) {
              final length = value.text.characters.length;
              if (length < limit * _counterVisibleRatio) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '$length / $limit',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    color: length >= limit
                        ? context.colors.destructive
                        : context.colors.textSecondary,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
