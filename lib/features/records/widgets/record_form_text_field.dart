import 'package:flutter/material.dart';
import 'package:recolle/core/theme/app_colors.dart';

class RecordFormTextField extends StatelessWidget {
  const RecordFormTextField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.hintText,
    this.maxLines = 1,
    this.maxLength,
    this.scrollPadding,
    this.focusNode,
    this.onChanged,
    this.textInputAction,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final String label;
  final IconData? icon;
  final String? hintText;
  final int maxLines;
  final int? maxLength;
  final TextInputAction? textInputAction;

  /// 未指定時は [TextField] 既定。キーボード表示時に ensureVisible が十分スクロールするよう拡げる。
  final EdgeInsets? scrollPadding;

  /// 常に「0/100」が並ぶと騒がしいので、上限が近づいてから出す。
  static const double _counterVisibleRatio = 0.8;

  @override
  Widget build(BuildContext context) {
    final multiline = maxLines > 1;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      minLines: multiline ? 2 : null,
      maxLines: maxLines,
      maxLength: maxLength,
      textInputAction:
          textInputAction ??
          (multiline ? TextInputAction.newline : TextInputAction.next),
      scrollPadding: scrollPadding ?? const EdgeInsets.all(20),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      cursorColor: AppColors.gold,
      buildCounter:
          (context, {required currentLength, required isFocused, maxLength}) {
            if (maxLength == null ||
                currentLength < maxLength * _counterVisibleRatio) {
              return null;
            }
            return Text(
              '$currentLength / $maxLength',
              style: TextStyle(
                fontSize: 11,
                color: currentLength >= maxLength
                    ? Colors.redAccent
                    : AppColors.textSecondary,
              ),
            );
          },
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        hintStyle: TextStyle(
          color: AppColors.textSecondary.withValues(alpha: 0.4),
          fontSize: 14,
        ),
        labelStyle: TextStyle(
          color: AppColors.textSecondary.withValues(alpha: 0.7),
        ),
        floatingLabelStyle: const TextStyle(color: AppColors.gold),
        prefixIcon: icon == null
            ? null
            : Icon(
                icon,
                color: AppColors.gold.withValues(alpha: 0.7),
                size: 20,
              ),
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.textDisabled.withValues(alpha: 0.12),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
        alignLabelWithHint: multiline,
      ),
    );
  }
}
