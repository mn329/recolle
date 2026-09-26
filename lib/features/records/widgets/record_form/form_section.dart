import 'package:flutter/material.dart';
import 'package:recolle/core/widgets/section_title.dart';

/// 作成フォームの 1 ブロック。見出しの下に子要素を縦に並べる。
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.japaneseLabel,
    required this.children,
    this.trailing,
    this.spacing = 12,
  });

  final String title;
  final String japaneseLabel;
  final Widget? trailing;
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            title,
            japaneseLabel,
            padding: EdgeInsets.zero,
            trailing: trailing,
          ),
          SizedBox(height: spacing + 2),
          ...children,
        ],
      ),
    );
  }
}
