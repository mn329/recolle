import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/features/records/ticket_mail_parser.dart';

/// チケットの購入・当選メールを貼り付けてもらい、読み取った項目を返す。キャンセル時は null。
Future<TicketMailInfo?> showTicketMailImportSheet(BuildContext context) {
  return showCupertinoSheet<TicketMailInfo>(
    context: context,
    builder: (_) => const _TicketMailImportSheet(),
  );
}

class _TicketMailImportSheet extends HookWidget {
  const _TicketMailImportSheet();

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController();
    useListenable(controller);
    final notFound = useState(false);

    void read() {
      final info = parseTicketMail(controller.text);
      if (info.isEmpty) {
        notFound.value = true;
        return;
      }
      Navigator.of(context).pop(info);
    }

    return CupertinoPageScaffold(
      backgroundColor: context.colors.background,
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        backgroundColor: context.colors.background,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 44),
          onPressed: () => Navigator.pop(context),
          child: Text(
            'キャンセル',
            style: TextStyle(color: context.colors.accent, fontSize: 17),
          ),
        ),
        middle: const Text('メールから入力'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 44),
          onPressed: controller.text.trim().isEmpty ? null : read,
          child: Text(
            '読み取る',
            style: TextStyle(
              color: controller.text.trim().isEmpty
                  ? context.colors.textDisabled
                  : context.colors.accent,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: CupertinoTextField(
                  controller: controller,
                  autofocus: true,
                  expands: true,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  placeholder: 'e+・ローチケ・チケットぴあなどの購入／当選メールの本文を貼り付けてください',
                  padding: const EdgeInsets.all(14),
                  style: TextStyle(
                    fontSize: 15,
                    color: context.colors.textPrimary,
                  ),
                  placeholderStyle: TextStyle(
                    fontSize: 15,
                    color: context.colors.textDisabled,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onChanged: (_) => notFound.value = false,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                notFound.value
                    ? '公演名・日付などを読み取れませんでした。「公演名：」「公演日：」のような行を含む本文を貼り付けてください。'
                    : '公演名・出演者・公演日・チケット取得元を読み取ります。本文は端末内で処理し、送信・保存しません。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: notFound.value
                      ? context.colors.destructive
                      : context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
