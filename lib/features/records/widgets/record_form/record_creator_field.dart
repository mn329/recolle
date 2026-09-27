import 'package:flutter/cupertino.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/widgets/music_suggestions.dart';
import 'package:recolle/features/records/widgets/record_form/form_text_row.dart';

/// アーティスト・監督・著者の入力欄。ライブではカタログの候補とお気に入りを添える。
class RecordCreatorField extends StatelessWidget {
  const RecordCreatorField({
    super.key,
    required this.type,
    required this.controller,
    required this.focusNode,
    required this.showSuggestions,
    required this.onChanged,
    required this.onPick,
    required this.scrollPadding,
  });

  final RecordType type;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// 入力中のカタログの候補を出すか。
  final bool showSuggestions;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onPick;
  final EdgeInsets scrollPadding;

  @override
  Widget build(BuildContext context) {
    // iTunes のカタログとお気に入りは音楽のみなので、ライブのときだけ出す
    final isLive = type == RecordType.live;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormTextRow(
          controller: controller,
          focusNode: focusNode,
          placeholder: type.creatorFieldLabel,
          icon: switch (type) {
            RecordType.live => CupertinoIcons.music_mic,
            RecordType.book => CupertinoIcons.pencil,
            RecordType.movie || RecordType.other => CupertinoIcons.person_2,
          },
          enLabel: type.creatorFieldEnLabel,
          maxLength: RecordFieldLimits.artistOrAuthor,
          scrollPadding: scrollPadding,
          onChanged: onChanged,
        ),
        if (isLive && showSuggestions)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ArtistSuggestions(
              query: controller.text,
              onPick: (a) => onPick(a.name),
            ),
          ),
        if (isLive)
          FavoriteArtistQuickPick(
            currentArtist: controller.text,
            onPick: (a) => onPick(a.name),
          ),
      ],
    );
  }
}
