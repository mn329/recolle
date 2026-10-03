import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/features/records/data/venue_search_client.dart';
import 'package:recolle/features/records/field_suggestions.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/venue_search_provider.dart';
import 'package:recolle/features/records/widgets/record_form/field_suggestion_chips.dart';
import 'package:recolle/features/records/widgets/record_form/form_text_row.dart';
import 'package:uuid/uuid.dart';

/// 会場の入力行。過去に使った会場と定番の会場に、地図（Google Places）から引いた候補を足して出す。
///
/// 地図の候補は名前が Places の表記に揃うので、同じ会場が記録ごとにばらけにくい。
/// 検索が使えないとき（未設定・圏外・失敗）は今まで通り履歴と定番だけを出す。
class RecordVenueRow extends HookConsumerWidget {
  const RecordVenueRow({
    super.key,
    required this.type,
    required this.controller,
    required this.onChanged,
    required this.scrollPadding,
  });

  /// 入力が落ち着くまで待つ時間。1 文字ごとに問い合わせると課金が膨らむ。
  static const _debounce = Duration(milliseconds: 400);

  static const _uuid = Uuid();

  final RecordType type;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final EdgeInsets scrollPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focusNode = useFocusNode();
    final focused = useListenableSelector(focusNode, () => focusNode.hasFocus);
    final query = useValueListenable(controller).text.trim();
    final mapResults = useState<List<String>>(const []);
    // 「入力しながら 1 つ選ぶ」までを Google に 1 回として数えさせる
    final sessionToken = useRef(_uuid.v4());

    useEffect(() {
      if (!kVenueMapSearchEnabled ||
          !focused ||
          query.length < VenueSearchClient.minQueryLength) {
        mapResults.value = const [];
        return null;
      }
      var cancelled = false;
      final timer = Timer(_debounce, () async {
        try {
          final venues = await ref
              .read(venueSearchClientProvider)
              .search(query, sessionToken: sessionToken.value);
          if (!cancelled) {
            mapResults.value = [for (final v in venues) v.name];
          }
        } catch (e) {
          // 候補は補助なので、出せなくても入力は続けられる
          debugPrint('venue search failed: $e');
          if (!cancelled) mapResults.value = const [];
        }
      });
      return () {
        cancelled = true;
        timer.cancel();
      };
    }, [query, focused]);

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
          onChanged: onChanged,
        ),
        FieldSuggestionChips(
          controller: controller,
          focusNode: focusNode,
          suggestionsFor: (records, text) => venueSuggestions(
            records: records,
            type: type,
            query: text,
            mapResults: mapResults.value,
          ),
          onPick: (value) {
            controller.value = TextEditingValue(
              text: value,
              selection: TextSelection.collapsed(offset: value.length),
            );
            onChanged(value);
            // 次の会場を探すときは別の検索として数えさせる
            sessionToken.value = _uuid.v4();
            mapResults.value = const [];
          },
        ),
      ],
    );
  }
}
