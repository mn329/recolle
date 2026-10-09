import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';

/// 入力欄にフォーカスがある間、その下に候補のチップを横に並べる。押すとその値を入れる。
///
/// 候補は [suggestionsFor] が自分の記録と入力中の文字から作る。
class FieldSuggestionChips extends HookConsumerWidget {
  const FieldSuggestionChips({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.suggestionsFor,
    required this.onPick,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> Function(List<Record> records, String query)
  suggestionsFor;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focused = useListenableSelector(focusNode, () => focusNode.hasFocus);
    final text = useValueListenable(controller).text;
    final records =
        ref.watch(recordsProvider).asData?.value ?? const <Record>[];
    final items = focused ? suggestionsFor(records, text) : const <String>[];

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: items.isEmpty
          ? const SizedBox(width: double.infinity)
          // チップを押しても入力欄の外を押したことにせず、キーボードを閉じない
          : TextFieldTapRegion(
              child: SizedBox(
                height: 44,
                // 作成画面はドラッグでキーボードを閉じるため、チップの横スクロールを伝えると
                // 入力欄のフォーカスが外れて候補ごと消えてしまう
                child: NotificationListener<ScrollNotification>(
                  onNotification: (_) => true,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => CapsuleChip(
                      label: items[index],
                      selected: false,
                      onTap: () => onPick(items[index]),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
