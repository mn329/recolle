import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';

/// Apple Music のような太字の和文見出しに、印字風の英字を小さく添える。
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title,
    this.japaneseLabel, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 0),
    this.trailing,
  });

  /// 見出しの上に小さく添える英字。
  final String title;
  final String japaneseLabel;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppFonts.monoStyle(
                    fontSize: 11,
                    color: context.colors.accent,
                  ).copyWith(letterSpacing: 1.6),
                ),
                const SizedBox(height: 2),
                Text(
                  japaneseLabel,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
