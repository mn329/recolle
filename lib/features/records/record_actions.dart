import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/app_toast.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/screens/create_record_screen.dart';
import 'package:recolle/features/records/screens/detail_screen.dart';

void openRecordDetail(BuildContext context, Record record) {
  Navigator.push(
    context,
    CupertinoPageRoute<void>(builder: (_) => DetailScreen(record: record)),
  );
}

/// 作成・編集フォームを iOS のシートで開き、保存された [Record] を返す。
///
/// 新規作成のときは、保存後にその記録の詳細を開く。
Future<Record?> openRecordEditor(
  BuildContext context, {
  Record? recordToEdit,
  String? initialArtist,
  RecordType? initialType,
}) async {
  final navigator = Navigator.of(context);
  final saved = await showCupertinoSheet<Record>(
    context: context,
    // 入力途中の内容をスワイプ一つで失わないよう、閉じるのはボタン（破棄確認つき）に限る
    enableDrag: false,
    builder: (_) => CreateRecordScreen(
      recordToEdit: recordToEdit,
      initialArtist: initialArtist,
      initialType: initialType,
    ),
  );
  if (saved != null && recordToEdit == null) {
    navigator.push(
      CupertinoPageRoute<void>(builder: (_) => DetailScreen(record: saved)),
    );
  }
  return saved;
}

/// アクションシートで確認してから記録を削除する。削除したら true。
Future<bool> confirmAndDeleteRecord(
  BuildContext context,
  WidgetRef ref,
  Record record,
) async {
  final ok = await showActionSheet<bool>(
    context,
    message: '「${record.title}」を削除すると元に戻せません。',
    actions: const [
      SheetAction(label: '記録を削除', value: true, isDestructive: true),
    ],
  );
  if (ok != true) return false;

  try {
    await ref.read(recordsRepositoryProvider).deleteRecord(record.id);
    ref.invalidate(recordsProvider);
    HapticFeedback.mediumImpact();
    AppToast.show('記録を削除しました', icon: CupertinoIcons.trash);
    return true;
  } catch (e) {
    AppToast.error('削除に失敗しました。${toUserFriendlyMessage(e)}');
    return false;
  }
}
