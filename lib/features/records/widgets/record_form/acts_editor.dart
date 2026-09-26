import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/widgets/music_suggestions.dart';
import 'package:recolle/features/records/widgets/record_form/form_row_parts.dart';
import 'package:recolle/features/records/widgets/record_form/form_section.dart';
import 'package:recolle/features/records/widgets/record_form/setlist_editor.dart';

/// 並び替えや削除をしても入力欄の状態を取り違えないための、出演者の安定キー。
class _ActDraft {
  const _ActDraft({required this.id, required this.act});

  final String id;
  final RecordAct act;
}

/// 対バン・フェスの出演者の入力欄。出演者ごとにお目当ての印とセトリを持つ。
class ActsEditor extends HookWidget {
  const ActsEditor({
    super.key,
    required this.initialActs,
    required this.onChanged,
    this.scrollPadding = const EdgeInsets.all(20),
  });

  /// DB の制約と揃える。
  static const int maxActs = 100;

  final List<RecordAct> initialActs;
  final ValueChanged<List<RecordAct>> onChanged;
  final EdgeInsets scrollPadding;

  @override
  Widget build(BuildContext context) {
    final idCounter = useRef(0);
    _ActDraft draft(RecordAct act) =>
        _ActDraft(id: 'act_${idCounter.value++}', act: act);

    final drafts = useState<List<_ActDraft>>(
      useMemoized(
        () => initialActs.isEmpty
            ? [draft(const RecordAct(artist: ''))]
            : initialActs.map(draft).toList(),
      ),
    );
    // 追加した出演者の名前欄にだけフォーカスを当てる
    final autofocusId = useState<String?>(null);

    void commit(List<_ActDraft> next) {
      drafts.value = next;
      onChanged([for (final d in next) d.act]);
    }

    void update(String id, RecordAct Function(RecordAct) change) => commit([
      for (final d in drafts.value)
        if (d.id == id) _ActDraft(id: d.id, act: change(d.act)) else d,
    ]);

    void add() {
      if (drafts.value.length >= maxActs) return;
      HapticFeedback.selectionClick();
      final added = draft(const RecordAct(artist: ''));
      autofocusId.value = added.id;
      commit([...drafts.value, added]);
    }

    void remove(String id) {
      HapticFeedback.selectionClick();
      commit([
        for (final d in drafts.value)
          if (d.id != id) d,
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, d) in drafts.value.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
            child: _ActCard(
              key: ValueKey(d.id),
              act: d.act,
              order: index + 1,
              autofocus: autofocusId.value == d.id,
              canRemove: drafts.value.length > 1,
              scrollPadding: scrollPadding,
              onArtistChanged: (name) =>
                  update(d.id, (a) => a.copyWith(artist: name)),
              onMainToggled: () {
                HapticFeedback.selectionClick();
                update(d.id, (a) => a.copyWith(isMain: !a.isMain));
              },
              onSongsChanged: (songs) =>
                  update(d.id, (a) => a.copyWith(songs: songs)),
              onRemove: () => remove(d.id),
            ),
          ),
        if (drafts.value.length < maxActs)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 12),
            onPressed: add,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.plus_circle_fill,
                  size: 20,
                  color: context.colors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  '出演者を追加',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.colors.accent,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ActCard extends StatefulWidget {
  const _ActCard({
    super.key,
    required this.act,
    required this.order,
    required this.autofocus,
    required this.canRemove,
    required this.scrollPadding,
    required this.onArtistChanged,
    required this.onMainToggled,
    required this.onSongsChanged,
    required this.onRemove,
  });

  final RecordAct act;

  /// 出演順（1 始まり）。
  final int order;
  final bool autofocus;
  final bool canRemove;
  final EdgeInsets scrollPadding;
  final ValueChanged<String> onArtistChanged;
  final VoidCallback onMainToggled;
  final ValueChanged<List<String>> onSongsChanged;
  final VoidCallback onRemove;

  @override
  State<_ActCard> createState() => _ActCardState();
}

class _ActCardState extends State<_ActCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.act.artist,
  );
  final FocusNode _focusNode = FocusNode();

  /// 候補から選んだ直後は同じ候補を出し直さない。
  bool _typedSincePick = false;
  bool _setlistOpen = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _pick(String name) {
    _controller.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    widget.onArtistChanged(name);
    setState(() => _typedSincePick = false);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final act = widget.act;
    final artist = act.artist.trim();
    final songCount = act.songs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormCard(
          children: [
            FormRowHighlight(
              active: _focusNode.hasFocus,
              child: Row(
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                    minimumSize: const Size(44, 44),
                    onPressed: widget.onMainToggled,
                    child: Icon(
                      act.isMain
                          ? CupertinoIcons.star_fill
                          : CupertinoIcons.star,
                      size: 21,
                      color: act.isMain ? colors.accent : colors.textDisabled,
                      semanticLabel: act.isMain ? 'お目当てを外す' : 'お目当てにする',
                    ),
                  ),
                  Expanded(
                    child: CupertinoTextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      placeholder: '${widget.order}組目の出演者',
                      maxLength: RecordFieldLimits.artistOrAuthor,
                      textInputAction: TextInputAction.done,
                      scrollPadding: widget.scrollPadding,
                      clearButtonMode: OverlayVisibilityMode.editing,
                      decoration: null,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      cursorColor: colors.accent,
                      style: TextStyle(fontSize: 16, color: colors.textPrimary),
                      placeholderStyle: TextStyle(
                        fontSize: 16,
                        color: colors.textDisabled,
                      ),
                      onChanged: (text) {
                        widget.onArtistChanged(text);
                        if (!_typedSincePick) {
                          setState(() => _typedSincePick = true);
                        }
                      },
                    ),
                  ),
                  if (widget.canRemove)
                    CupertinoButton(
                      padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
                      minimumSize: const Size(44, 44),
                      onPressed: widget.onRemove,
                      child: Icon(
                        CupertinoIcons.minus_circle_fill,
                        size: 21,
                        color: colors.destructive,
                        semanticLabel: '出演者を削除',
                      ),
                    )
                  else
                    const SizedBox(width: 14),
                ],
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.fromLTRB(16, 8, 14, 8),
              minimumSize: const Size(0, 44),
              pressedOpacity: 0.6,
              onPressed: () => setState(() => _setlistOpen = !_setlistOpen),
              child: Row(
                children: [
                  FormRowIcon(CupertinoIcons.music_note_list),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'セットリスト',
                      style: TextStyle(fontSize: 15, color: colors.textPrimary),
                    ),
                  ),
                  Text(
                    songCount == 0 ? '未入力' : '$songCount曲',
                    style: TextStyle(fontSize: 15, color: colors.textSecondary),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _setlistOpen ? 0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      CupertinoIcons.chevron_right,
                      size: 15,
                      color: colors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_focusNode.hasFocus && _typedSincePick)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: ArtistSuggestions(
              query: _controller.text,
              onPick: (a) => _pick(a.name),
            ),
          ),
        if (_setlistOpen)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SetlistEditor(
              initialSongs: act.songs,
              artistName: artist,
              scrollPadding: widget.scrollPadding,
              onChanged: widget.onSongsChanged,
            ),
          ),
      ],
    );
  }
}
