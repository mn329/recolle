import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/components/record_ticket_card.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/screens/create_record_screen.dart';
import 'package:recolle/features/records/screens/detail_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(recordsProvider);
    final readOnlyOffline = ref.watch(isOfflineReadOnlyProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            'RECOLLE',
            style: AppFonts.displayStyle(
              fontSize: 30,
              color: AppColors.gold,
              letterSpacing: 3,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                Icons.add,
                color: readOnlyOffline
                    ? AppColors.textDisabled
                    : AppColors.gold,
              ),
              tooltip:
                  readOnlyOffline ? 'オフラインでは新規作成できません' : '記録を追加',
              onPressed: readOnlyOffline
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CreateRecordScreen(),
                          fullscreenDialog: true,
                        ),
                      );
                    },
            ),
          ],
          bottom: TabBar(
            isScrollable: false,
            indicatorColor: AppColors.gold,
            labelColor: AppColors.gold,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: RecordType.values
                .map((t) => Tab(text: t.japaneseLabel))
                .toList(),
          ),
        ),
        body: recordsAsync.when(
          data: (records) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (readOnlyOffline)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: AppColors.surfaceLight,
                  child: const Row(
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'オフラインです。キャッシュがある記録は閲覧のみできます。',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildRecordList(context, records, RecordType.live),
                    _buildRecordList(context, records, RecordType.movie),
                    _buildRecordList(context, records, RecordType.book),
                    _buildRecordList(context, records, RecordType.other),
                  ],
                ),
              ),
            ],
          ),
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.gold),
          ),
          error: (error, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                toUserFriendlyMessage(error),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordList(
    BuildContext context,
    List<Record> allRecords,
    RecordType type,
  ) {
    final filteredRecords = allRecords
        .where((record) => record.type == type)
        .toList();

    if (filteredRecords.isEmpty) {
      return const Center(
        child: Text(
          '記録がありません',
          style: TextStyle(color: AppColors.textDisabled),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: filteredRecords.length,
      itemBuilder: (context, index) {
        final record = filteredRecords[index];
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
