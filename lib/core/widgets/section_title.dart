import 'package:flutter/material.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';

/// 英字の印字風見出しに、和文の小さなラベルを添える。
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title,
    this.japaneseLabel, {
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
    this.trailing,
  });

  final String title;
  final String japaneseLabel;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: AppFonts.displayStyle(
              fontSize: 24,
              color: AppColors.gold,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              japaneseLabel,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
