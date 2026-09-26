import 'package:flutter/material.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/features/records/models/record.dart';

/// 記録の種別を選ぶ 4 分割のタイル。
class RecordTypeSelector extends StatelessWidget {
  const RecordTypeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final RecordType selected;
  final ValueChanged<RecordType> onChanged;

  static IconData iconOf(RecordType type) => switch (type) {
    RecordType.live => Icons.mic_external_on_outlined,
    RecordType.movie => Icons.movie_outlined,
    RecordType.book => Icons.menu_book_outlined,
    RecordType.other => Icons.auto_awesome_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (index, type) in RecordType.values.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: _TypeTile(
              type: type,
              selected: type == selected,
              onTap: () => onChanged(type),
            ),
          ),
        ],
      ],
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final RecordType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.black : AppColors.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? AppColors.gold : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : AppColors.textDisabled.withValues(alpha: 0.15),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    RecordTypeSelector.iconOf(type),
                    size: 22,
                    color: foreground,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    type.japaneseLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: foreground,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
