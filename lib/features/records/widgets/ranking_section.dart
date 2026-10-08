import 'package:flutter/widgets.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';

/// ランキングの 1 行。[onTap] が null なら押せない。
typedef RankingRow = ({
  String title,
  String? subtitle,
  int count,
  VoidCallback? onTap,
});

/// 順位・名前・回数を並べる振り返りのランキング。行がなければ何も出さない。
class RankingSection extends StatelessWidget {
  const RankingSection({super.key, required this.header, required this.rows});

  final String header;
  final List<RankingRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    return InsetGroupedSection(
      header: header,
      children: [
        for (final (i, row) in rows.indexed)
          GroupedRow(
            leading: SizedBox(
              width: 24,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.center,
                style: AppFonts.monoStyle(fontSize: 15, color: colors.accent),
              ),
            ),
            title: row.title,
            subtitle: row.subtitle,
            additionalInfo: Text(
              '${row.count}回',
              style: TextStyle(fontSize: 15, color: colors.textSecondary),
            ),
            onTap: row.onTap,
          ),
      ],
    );
  }
}
