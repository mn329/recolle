import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/widgets/music_suggestions.dart';
import 'package:recolle/features/records/widgets/record_form/form_text_row.dart';
import 'package:uuid/uuid.dart';

/// 会場の入力行。入力欄にフォーカスがある間、その下に会場の候補を縦に並べる。
///
/// 候補は過去に使った会場と定番の会場に、地図（Google Places）から引いた会場（住所つき）を足したもの。
/// 地図の候補は名前が Places の表記に揃うので、同じ会場が記録ごとにばらけにくい。
class RecordVenueRow extends HookConsumerWidget {
  const RecordVenueRow({
    super.key,
    required this.type,
    required this.controller,
    required this.onChanged,
    required this.scrollPadding,
  });

  static const _uuid = Uuid();

  final RecordType type;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final EdgeInsets scrollPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focusNode = useFocusNode();
    final focused = useListenableSelector(focusNode, () => focusNode.hasFocus);
    final text = useValueListenable(controller).text;
    // 候補から選んだ直後は、同じ候補を出し直さない
    final picked = useState(false);
    final sessionToken = useRef(_uuid.v4());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormTextRow(
          controller: controller,
          focusNode: focusNode,
          placeholder: type.venueLabel!,
          icon: CupertinoIcons.location,
          enLabel: type.venueEnLabel,
          maxLength: RecordFieldLimits.venue,
          scrollPadding: scrollPadding,
          onChanged: (value) {
            picked.value = false;
            onChanged(value);
          },
        ),
        if (focused && !picked.value)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: VenueSuggestions(
              type: type,
              query: text,
              sessionToken: sessionToken.value,
              onPick: (value) {
                controller.value = TextEditingValue(
                  text: value,
                  selection: TextSelection.collapsed(offset: value.length),
                );
                onChanged(value);
                picked.value = true;
                // 次の会場を探すときは別の検索として数えさせる
                sessionToken.value = _uuid.v4();
                focusNode.unfocus();
              },
            ),
          ),
      ],
    );
  }
}
