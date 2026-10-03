import 'package:flutter/cupertino.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/features/records/concert_candidates.dart';
import 'package:recolle/features/records/data/work_search_client.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/widgets/music_suggestions.dart';
import 'package:recolle/features/records/widgets/record_form/form_text_row.dart';

/// 公演名・作品名・書名の入力欄。ライブは公演の候補、映画・本は作品の候補を添える。
class RecordTitleField extends StatelessWidget {
  const RecordTitleField({
    super.key,
    required this.type,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.lookupArtist,
    required this.showSuggestions,
    required this.onChanged,
    required this.onPickConcert,
    required this.onPickWork,
    required this.scrollPadding,
  });

  final RecordType type;
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// 公演の候補を引くアーティスト。空なら候補を出さない。
  final String lookupArtist;

  /// 候補を出すか（候補から選んだ直後は出し直さない）。
  final bool showSuggestions;
  final ValueChanged<String> onChanged;
  final ValueChanged<ConcertCandidate> onPickConcert;
  final ValueChanged<WorkSuggestion> onPickWork;
  final EdgeInsets scrollPadding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormTextRow(
          controller: controller,
          focusNode: focusNode,
          placeholder: label,
          icon: switch (type) {
            RecordType.live => CupertinoIcons.music_note_2,
            RecordType.movie => CupertinoIcons.film,
            RecordType.book => CupertinoIcons.book,
            RecordType.other => CupertinoIcons.star,
          },
          enLabel: 'TITLE',
          maxLength: RecordFieldLimits.title,
          scrollPadding: scrollPadding,
          onChanged: onChanged,
        ),
        if (showSuggestions &&
            type == RecordType.live &&
            lookupArtist.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ConcertSuggestions(
              artist: lookupArtist,
              query: controller.text,
              onPick: onPickConcert,
            ),
          ),
        if (showSuggestions &&
            (type == RecordType.movie || type == RecordType.book))
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: WorkSuggestions(
              key: ValueKey(type),
              type: type,
              query: controller.text,
              onPick: onPickWork,
            ),
          ),
      ],
    );
  }
}
