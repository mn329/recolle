import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, ReorderableListView;
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/widgets/app_toast.dart';
import 'package:recolle/features/records/models/setlist_entry.dart';
import 'package:recolle/features/records/widgets/music_suggestions.dart';
import 'package:recolle/features/records/widgets/record_form/form_section.dart';

/// 並び替え時に [ReorderableListView] 用の安定キーとなる行。
class _SetlistLine {
  const _SetlistLine({required this.id, required this.text});

  final String id;
  final String text;
}

/// セットリストの入力欄。曲の追加・編集・並び替え・削除を担う。
class SetlistEditor extends HookWidget {
  const SetlistEditor({
    super.key,
    required this.initialSongs,
    required this.artistName,
    required this.onChanged,
    this.scrollPadding = const EdgeInsets.all(20),
    this.embedded = false,
  });

  final List<String> initialSongs;

  /// 出演者のカードなど、角丸の背景を持つ親の中に置くとき true（自前の枠を描かない）。
  final bool embedded;

  /// 曲名候補の検索に使う。
  final String artistName;
  final ValueChanged<List<String>> onChanged;
  final EdgeInsets scrollPadding;

  @override
  Widget build(BuildContext context) {
    final idCounter = useRef(0);
    _SetlistLine newLine(String text) =>
        _SetlistLine(id: 'sl_${idCounter.value++}', text: text);

    final lines = useState<List<_SetlistLine>>(
      useMemoized(() => initialSongs.map(newLine).toList()),
    );
    final inputController = useTextEditingController();
    final inputText = useValueListenable(inputController).text;
    final inputFocusNode = useFocusNode();
    useListenable(inputFocusNode);
    final inputKey = useMemoized(GlobalKey.new);
    // 並び替え中の触覚用。つまんでいる行と、指の下にある行
    final draggingId = useRef<String?>(null);
    final hoveredId = useRef<String?>(null);
    final rowContexts = useMemoized(() => <String, BuildContext>{});
    final lineIds = {for (final l in lines.value) l.id};
    rowContexts.removeWhere((id, _) => !lineIds.contains(id));

    void commit(List<_SetlistLine> next) {
      lines.value = next;
      onChanged([for (final line in next) line.text]);
    }

    /// [texts] を [index]（省略時は末尾）に入れる。全体の文字数を超えるなら入れずに false。
    bool insertLines(List<String> texts, {int? index}) {
      final current = lines.value;
      final totalLength = [
        ...current.map((e) => e.text),
        ...texts,
      ].join('\n').length;
      if (totalLength > RecordFieldLimits.setlistTotal) {
        AppToast.error('セットリスト全体は最大${RecordFieldLimits.setlistTotal}文字までです。');
        return false;
      }
      HapticFeedback.selectionClick();
      final at = index ?? current.length;
      commit([...current.take(at), ...texts.map(newLine), ...current.skip(at)]);
      return true;
    }

    void keepInputVisible() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final target = inputKey.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
        inputFocusNode.requestFocus();
      });
    }

    void addSong() {
      final song = inputController.text.trim();
      if (song.isEmpty) return;
      if (song.length > RecordFieldLimits.setlistSongLine) {
        AppToast.error('曲名は最大${RecordFieldLimits.setlistSongLine}文字までです。');
        return;
      }
      if (!insertLines([song])) return;
      inputController.clear();
      keepInputVisible();
    }

    // 「＋」を押さないまま入力欄を離れた（保存を押した）ときも、書きかけの曲を落とさない
    useEffect(() {
      void commitPending() {
        if (inputFocusNode.hasFocus) return;
        final song = inputController.text.trim();
        if (song.isEmpty || song.length > RecordFieldLimits.setlistSongLine) {
          return;
        }
        if (insertLines([song])) inputController.clear();
      }

      inputFocusNode.addListener(commitPending);
      return () => inputFocusNode.removeListener(commitPending);
    }, [inputFocusNode]);

    /// 複数行が貼り付けられたら、行ごとに曲（区切り・MC）として追加する。
    void onInputChanged(String text) {
      if (!text.contains('\n') && !text.contains('\r')) return;
      final pasted = [
        for (final line in parsePastedSetlist(text))
          line.length > RecordFieldLimits.setlistSongLine
              ? line.substring(0, RecordFieldLimits.setlistSongLine)
              : line,
      ];
      inputController.clear();
      if (pasted.isEmpty || !insertLines(pasted)) return;
      final songCount = setlistSongTitles(pasted).length;
      AppToast.show('$songCount曲を追加しました', icon: CupertinoIcons.music_note_list);
      keepInputVisible();
    }

    // ボタンの処理では、同じフレームで続けて押されても重ならないよう最新の行から数え直す
    List<String> currentSections() => [
      for (final l in lines.value)
        if (SetlistEntry.parse(l.text) case SetlistEntry(
          kind: SetlistEntryKind.section,
          :final label,
        ))
          label,
    ];

    /// 次に入れるのが「リハ」か「本番」か。両方あれば null。
    String? nextRehearsalSection() {
      final sections = currentSections();
      if (!sections.contains(SetlistSections.rehearsal)) {
        return SetlistSections.rehearsal;
      }
      if (!sections.contains(SetlistSections.main)) return SetlistSections.main;
      return null;
    }

    void addEncore() {
      final count = currentSections()
          .where((s) => s.startsWith(SetlistSections.encore))
          .length;
      insertLines([
        SetlistEntry.section(
          count == 0
              ? SetlistSections.encore
              : '${SetlistSections.encore}${count + 1}',
        ).line,
      ]);
    }

    // リハは公演の最初なので先頭に、本番はリハの曲を入れ終えたところ（末尾）に入れる
    void addRehearsalSection() {
      final next = nextRehearsalSection();
      if (next == null) return;
      insertLines([
        SetlistEntry.section(next).line,
      ], index: next == SetlistSections.rehearsal ? 0 : null);
    }

    final entries = [for (final l in lines.value) SetlistEntry.parse(l.text)];
    final songCount = entries.where((e) => e.isSong).length;

    void removeAt(int index) {
      final removed = lines.value[index];
      commit([...lines.value]..removeAt(index));
      AppToast.show(
        '「${SetlistEntry.parse(removed.text).label}」を削除しました',
        icon: CupertinoIcons.trash,
        actionLabel: '元に戻す',
        onAction: () {
          if (!context.mounted) return;
          final restored = [...lines.value];
          restored.insert(index.clamp(0, restored.length), removed);
          commit(restored);
        },
      );
    }

    /// 指の下にある行（つまんでいる行を除く）が変わるたびに、iOS の並び替えと同じく軽く鳴らす。
    void onDragMove(PointerMoveEvent event) {
      final dragging = draggingId.value;
      if (dragging == null) return;
      String? hovered;
      for (final MapEntry(key: id, value: row) in rowContexts.entries) {
        if (id == dragging || !row.mounted) continue;
        final box = row.findRenderObject();
        if (box is! RenderBox || !box.hasSize) continue;
        final top = box.localToGlobal(Offset.zero).dy;
        if (event.position.dy >= top &&
            event.position.dy < top + box.size.height) {
          hovered = id;
          break;
        }
      }
      if (hovered != null && hovered != hoveredId.value) {
        HapticFeedback.selectionClick();
      }
      hoveredId.value = hovered ?? hoveredId.value;
    }

    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lines.value.isNotEmpty)
          Listener(
            onPointerMove: onDragMove,
            child: ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              padding: EdgeInsets.zero,
              proxyDecorator: (child, _, _) => Material(
                color: context.colors.cardPressed,
                elevation: 8,
                shadowColor: CupertinoColors.black,
                borderRadius: BorderRadius.circular(10),
                child: child,
              ),
              onReorderStart: (index) {
                HapticFeedback.mediumImpact();
                draggingId.value = lines.value[index].id;
                hoveredId.value = null;
              },
              onReorderEnd: (_) => draggingId.value = null,
              onReorder: (oldIndex, newIndex) {
                final items = [...lines.value];
                if (newIndex > oldIndex) newIndex--;
                items.insert(newIndex, items.removeAt(oldIndex));
                HapticFeedback.lightImpact();
                commit(items);
              },
              children: [
                for (final (index, line) in lines.value.indexed)
                  Dismissible(
                    key: ValueKey(line.id),
                    direction: DismissDirection.endToStart,
                    background: const _DeleteBackground(),
                    onDismissed: (_) => removeAt(index),
                    child: _RowProbe(
                      id: line.id,
                      registry: rowContexts,
                      child: entries[index].isSong
                          ? _SongRow(
                              number: entries
                                  .take(index + 1)
                                  .where((e) => e.isSong)
                                  .length,
                              index: index,
                              text: line.text,
                              scrollPadding: scrollPadding,
                              onChanged: (text) => commit([
                                for (final e in lines.value)
                                  if (e.id == line.id)
                                    _SetlistLine(id: e.id, text: text)
                                  else
                                    e,
                              ]),
                            )
                          : _MarkerRow(entry: entries[index], index: index),
                    ),
                  ),
              ],
            ),
          ),
        _AddSongInput(
          key: inputKey,
          controller: inputController,
          focusNode: inputFocusNode,
          nextNumber: songCount + 1,
          hasSongs: songCount > 0,
          scrollPadding: scrollPadding,
          onSubmit: addSong,
          onChanged: onInputChanged,
        ),
        const FormDivider(indent: 16),
        _QuickInsertBar(
          onMc: () => insertLines([SetlistEntry.mc.line]),
          onEncore: addEncore,
          rehearsalLabel: nextRehearsalSection(),
          onRehearsal: addRehearsalSection,
        ),
      ],
    );
    final suggestions = SongSuggestions(
      artistName: artistName,
      query: inputText,
      showPopularWhenEmpty: inputFocusNode.hasFocus,
      alreadyAdded: [
        for (final e in entries)
          if (e.isSong) e.label,
      ],
      onPick: (song) {
        inputController.text = song.title;
        addSong();
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 各曲の行が自分の下に区切り線を引くので、FormCard の自動の区切り線は使わない
        if (embedded)
          rows
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(color: context.colors.card, child: rows),
          ),
        if (embedded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: suggestions,
          )
        else
          suggestions,
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, embedded ? 12 : 0),
          child: Text(
            [
              if (lines.value.length > 1) '右端のつまみで並び替え、左にスワイプで削除できます。',
              '複数行のセトリを貼り付けると、1 行ずつ追加します。',
            ].join(),
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.destructive,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.only(right: 20),
          child: Icon(CupertinoIcons.trash, color: CupertinoColors.white),
        ),
      ),
    );
  }
}

class _SongNumber extends StatelessWidget {
  const _SongNumber(this.number, {this.dimmed = false});

  final int number;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: Text(
        number.toString().padLeft(2, '0'),
        style: AppFonts.monoStyle(
          fontSize: 13,
          color: context.colors.accent.withValues(alpha: dimmed ? 0.35 : 0.8),
        ),
      ),
    );
  }
}

/// セトリの曲名入力に共通の見た目。
CupertinoTextField _songTextField(
  BuildContext context, {
  required TextEditingController controller,
  required FocusNode focusNode,
  required EdgeInsets scrollPadding,
  String? placeholder,
  int maxLines = 1,
  int? maxLength = RecordFieldLimits.setlistSongLine,
  TextInputAction? textInputAction,
  ValueChanged<String>? onChanged,
  VoidCallback? onEditingComplete,
}) {
  return CupertinoTextField(
    controller: controller,
    focusNode: focusNode,
    scrollPadding: scrollPadding,
    maxLength: maxLength,
    minLines: 1,
    maxLines: maxLines,
    placeholder: placeholder,
    textInputAction: textInputAction,
    decoration: null,
    padding: const EdgeInsets.symmetric(vertical: 13),
    cursorColor: context.colors.accent,
    style: TextStyle(fontSize: 16, color: context.colors.textPrimary),
    placeholderStyle: TextStyle(
      fontSize: 16,
      color: context.colors.textDisabled,
    ),
    onChanged: onChanged,
    onEditingComplete: onEditingComplete,
  );
}

class _SongRow extends StatefulWidget {
  const _SongRow({
    required this.number,
    required this.index,
    required this.text,
    required this.scrollPadding,
    required this.onChanged,
  });

  final int number;

  /// [ReorderableDragStartListener] に渡す現在位置。
  final int index;
  final String text;
  final EdgeInsets scrollPadding;
  final ValueChanged<String> onChanged;

  @override
  State<_SongRow> createState() => _SongRowState();
}

class _SongRowState extends State<_SongRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant _SongRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 入力中に外から上書きするとカーソルが飛ぶので、フォーカスが無いときだけ同期する
    if (!_focusNode.hasFocus && widget.text != _controller.text) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.card,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                _SongNumber(widget.number),
                Expanded(
                  child: _songTextField(
                    context,
                    controller: _controller,
                    focusNode: _focusNode,
                    scrollPadding: widget.scrollPadding,
                    maxLines: 2,
                    onChanged: widget.onChanged,
                  ),
                ),
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Icon(
                      CupertinoIcons.line_horizontal_3,
                      size: 20,
                      color: context.colors.textDisabled,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const FormDivider(indent: 44),
        ],
      ),
    );
  }
}

/// 並び替え中に指の下の行を調べられるよう、行の [BuildContext] を [registry] に登録する。
/// 行はドラッグ中に浮かせた表示にも複製されるため、GlobalKey ではなくこの方法で持つ。
class _RowProbe extends StatelessWidget {
  const _RowProbe({
    required this.id,
    required this.registry,
    required this.child,
  });

  final String id;
  final Map<String, BuildContext> registry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    registry[id] = context;
    return child;
  }
}

/// アンコールなどの区切りと MC の行。番号を振らず、並び替え・削除だけできる。
class _MarkerRow extends StatelessWidget {
  const _MarkerRow({required this.entry, required this.index});

  final SetlistEntry entry;

  /// [ReorderableDragStartListener] に渡す現在位置。
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isSection = entry.kind == SetlistEntryKind.section;
    final color = isSection ? colors.accent : colors.textSecondary;
    return ColoredBox(
      color: colors.card,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Icon(
                    isSection ? CupertinoIcons.flag : CupertinoIcons.mic,
                    size: 15,
                    color: color,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Text(
                      entry.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSection ? FontWeight.w600 : null,
                        color: color,
                      ),
                    ),
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Icon(
                      CupertinoIcons.line_horizontal_3,
                      size: 20,
                      color: colors.textDisabled,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const FormDivider(indent: 44),
        ],
      ),
    );
  }
}

/// MC・アンコール・リハ／本番の行をワンタップで入れるボタン。
class _QuickInsertBar extends StatelessWidget {
  const _QuickInsertBar({
    required this.onMc,
    required this.onEncore,
    required this.rehearsalLabel,
    required this.onRehearsal,
  });

  final VoidCallback onMc;
  final VoidCallback onEncore;

  /// 次に入れるのが「リハ」か「本番」か。両方入っていれば null（ボタンを出さない）。
  final String? rehearsalLabel;
  final VoidCallback onRehearsal;

  @override
  Widget build(BuildContext context) {
    final label = rehearsalLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: _QuickInsertButton(
              icon: CupertinoIcons.mic,
              label: 'MC',
              onPressed: onMc,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickInsertButton(
              icon: CupertinoIcons.add,
              label: SetlistSections.encore,
              onPressed: onEncore,
            ),
          ),
          if (label != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: _QuickInsertButton(
                icon: CupertinoIcons.add,
                label: label,
                onPressed: onRehearsal,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickInsertButton extends StatelessWidget {
  const _QuickInsertButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 36),
      onPressed: onPressed,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.separator),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: colors.textSecondary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddSongInput extends StatelessWidget {
  const _AddSongInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.nextNumber,
    required this.hasSongs,
    required this.scrollPadding,
    required this.onSubmit,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int nextNumber;
  final bool hasSongs;
  final EdgeInsets scrollPadding;
  final VoidCallback onSubmit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Row(
        children: [
          _SongNumber(nextNumber, dimmed: true),
          Expanded(
            child: _songTextField(
              context,
              controller: controller,
              focusNode: focusNode,
              scrollPadding: scrollPadding,
              placeholder: hasSongs ? '次の曲を追加' : '1曲目の曲名を入力',
              // 1 行入力だと貼り付けた改行が消えるので複数行にする。改行キーは確定になる
              maxLines: 3,
              // 複数行の貼り付けが途中で切れないよう、1 曲の上限は確定時に確かめる
              maxLength: null,
              textInputAction: TextInputAction.done,
              onChanged: onChanged,
              // 連続入力しやすいよう、確定してもキーボードを閉じない
              onEditingComplete: onSubmit,
            ),
          ),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, value, _) {
              final enabled = value.text.trim().isNotEmpty;
              return CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(44, 44),
                onPressed: enabled ? onSubmit : null,
                child: Icon(
                  CupertinoIcons.plus_circle_fill,
                  size: 26,
                  color: enabled
                      ? context.colors.accent
                      : context.colors.textDisabled,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
