import 'package:flutter/material.dart';
import 'package:recolle/components/record_ticket_card.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/screens/detail_screen.dart';

/// チケットカードの縦リスト。タップで詳細画面を開く。
class RecordTicketList extends StatelessWidget {
  const RecordTicketList({
    super.key,
    required this.records,
    this.emptyMessage = '記録がありません',
    this.padding = const EdgeInsets.symmetric(vertical: 16),
  });

  final List<Record> records;
  final String emptyMessage;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textDisabled),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: padding,
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        return RecordTicketCard(
          record: record,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DetailScreen(record: record),
              ),
            );
          },
        );
      },
    );
  }
}
