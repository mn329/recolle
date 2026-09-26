import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/components/record_ticket_card.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_actions.dart';

/// タップで詳細、長押しで編集・削除のコンテキストメニューを出すチケット。
class RecordTicketTile extends ConsumerWidget {
  const RecordTicketTile({super.key, required this.record});

  final Record record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = RecordTicketCard(
      record: record,
      onTap: () => openRecordDetail(context, record),
    );
    if (ref.watch(isOfflineReadOnlyProvider)) return card;

    void closeMenuThen(VoidCallback action) {
      // メニューはルート Navigator に積まれるので、それを閉じてから操作する
      Navigator.of(context, rootNavigator: true).pop();
      action();
    }

    // プレビューは幅に制約のない FittedBox の中で描かれるので、一覧での幅に固定しておく
    return LayoutBuilder(
      builder: (context, constraints) => _buildMenu(
        context,
        ref,
        SizedBox(width: constraints.maxWidth, child: card),
        closeMenuThen,
      ),
    );
  }

  Widget _buildMenu(
    BuildContext context,
    WidgetRef ref,
    Widget card,
    void Function(VoidCallback action) closeMenuThen,
  ) {
    return CupertinoContextMenu(
      enableHapticFeedback: true,
      actions: [
        CupertinoContextMenuAction(
          trailingIcon: CupertinoIcons.doc_text,
          onPressed: () =>
              closeMenuThen(() => openRecordDetail(context, record)),
          child: const Text('詳細を見る'),
        ),
        CupertinoContextMenuAction(
          trailingIcon: CupertinoIcons.pencil,
          onPressed: () => closeMenuThen(
            () => openRecordEditor(context, recordToEdit: record),
          ),
          child: const Text('編集'),
        ),
        CupertinoContextMenuAction(
          isDestructiveAction: true,
          trailingIcon: CupertinoIcons.trash,
          onPressed: () =>
              closeMenuThen(() => confirmAndDeleteRecord(context, ref, record)),
          child: const Text('削除'),
        ),
      ],
      child: card,
    );
  }
}

/// [CustomScrollView] 用のチケット一覧。空なら画面中央に案内を出す。
class SliverRecordTicketList extends StatelessWidget {
  const SliverRecordTicketList({
    super.key,
    required this.records,
    this.emptyTitle,
    this.emptyMessage = '記録がありません',
    this.emptyActionLabel,
    this.onEmptyAction,
  });

  final List<Record> records;
  final String? emptyTitle;
  final String emptyMessage;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: IosEmptyState(
          icon: CupertinoIcons.tickets,
          title: emptyTitle,
          message: emptyMessage,
          actionLabel: emptyActionLabel,
          onAction: onEmptyAction,
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.only(top: 4),
      sliver: SliverList.builder(
        itemCount: records.length,
        itemBuilder: (context, index) =>
            RecordTicketTile(record: records[index]),
      ),
    );
  }
}
