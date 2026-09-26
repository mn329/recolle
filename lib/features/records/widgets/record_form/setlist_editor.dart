import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/features/records/widgets/music_suggestions.dart';
import 'package:recolle/features/records/widgets/setlistfm_import_sheet.dart';

/// 並び替え時に [ReorderableListView] 用の安定キーとなる行。
class _SetlistLine {
  const _SetlistLine({required this.id, required this.text});

  final String id;
  final String text;
}

/// セットリストの入力欄。曲の追加・編集・並び替え・削除と setlist.fm 取り込みを担う。
class SetlistEditor extends HookWidget {
  const SetlistEditor({
    super.key,
    required this.initialSongs,
    required this.artistName,
    required this.date,
    required this.onChanged,
    this.scrollPadding = const EdgeInsets.all(20),
  });

  final List<String> initialSongs;

  /// 曲名候補と setlist.fm 検索に使う。
  final String artistName;

  /// setlist.fm で公演を探すときの日付。
  final DateTime date;
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
    final inputKey = useMemoized(GlobalKey.new);

    void commit(List<_SetlistLine> next) {
      lines.value = next;
      onChanged([for (final line in next) line.text]);
    }

    void showMessage(String message, {SnackBarAction? action}) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message), action: action));
    }

    void addSong() {
      final song = inputController.text.trim();
      if (song.isEmpty) return;
      final totalLength = [
        ...lines.value.map((e) => e.text),
        song,
      ].join('\n').length;
      if (totalLength > RecordFieldLimits.setlistTotal) {
        showMessage('セットリスト全体は最大${RecordFieldLimits.setlistTotal}文字までです。');
        return;
      }
      commit([...lines.value, newLine(song)]);
      inputController.clear();
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

    void removeAt(int index) {
      final removed = lines.value[index];
      commit([...lines.value]..removeAt(index));
      showMessage(
        '「${removed.text}」を削除しました',
        action: SnackBarAction(
          label: '元に戻す',
          textColor: AppColors.gold,
          onPressed: () {
            if (!context.mounted) return;
            final restored = [...lines.value];
            restored.insert(index.clamp(0, restored.length), removed);
            commit(restored);
          },
        ),
      );
    }

    Future<void> importFromSetlistFm() async {
      FocusScope.of(context).unfocus();
      final songs = await showSetlistFmImportSheet(
        context,
        artistName: artistName.trim(),
        date: date,
      );
      if (songs == null || songs.isEmpty || !context.mounted) return;

      if (lines.value.isNotEmpty) {
        final replace = await showConfirmDialog(
          context,
          title: 'セットリストを置き換え',
          message:
              '入力済みの${lines.value.length}曲を、取り込んだ${songs.length}曲で置き換えますか？',
          okText: '置き換える',
        );
        if (!replace || !context.mounted) return;
      }

      final (imported, truncated) = _fitToLimits(songs);
      commit(imported.map(newLine).toList());
      showMessage(
        truncated
            ? '${imported.length}曲を取り込みました（文字数上限のため一部省略）'
            : '${imported.length}曲を取り込みました',
      );
    }

    final canImport = artistName.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: canImport ? importFromSetlistFm : null,
          icon: const Icon(Icons.cloud_download_outlined, size: 18),
          label: const Text('setlist.fm から取り込む'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.gold,
            side: BorderSide(
              color: canImport
                  ? AppColors.gold.withValues(alpha: 0.5)
                  : AppColors.textDisabled.withValues(alpha: 0.3),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        if (!canImport)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'アーティストを入力すると、公演日のセットリストを取り込めます',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary.withValues(alpha: 0.6),
              ),
            ),
          ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.textDisabled.withValues(alpha: 0.12),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (lines.value.isNotEmpty)
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    padding: EdgeInsets.zero,
                    proxyDecorator: (child, _, _) => Material(
                      color: AppColors.surface,
                      elevation: 6,
                      shadowColor: Colors.black,
                      child: child,
                    ),
                    onReorder: (oldIndex, newIndex) {
                      final items = [...lines.value];
                      if (newIndex > oldIndex) newIndex--;
                      items.insert(newIndex, items.removeAt(oldIndex));
                      commit(items);
                    },
                    children: [
                      for (final (index, line) in lines.value.indexed)
                        Dismissible(
                          key: ValueKey(line.id),
                          direction: DismissDirection.endToStart,
                          background: const _DeleteBackground(),
                          onDismissed: (_) => removeAt(index),
                          child: _SongRow(
                            number: index + 1,
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
                          ),
                        ),
                    ],
                  ),
                _AddSongInput(
                  key: inputKey,
                  controller: inputController,
                  focusNode: inputFocusNode,
                  nextNumber: lines.value.length + 1,
                  hasSongs: lines.value.isNotEmpty,
                  scrollPadding: scrollPadding,
                  onSubmit: addSong,
                ),
              ],
            ),
          ),
        ),
        SongSuggestions(
          artistName: artistName,
          query: inputText,
          alreadyAdded: lines.value.map((e) => e.text),
          onPick: (song) {
            inputController.text = song.title;
            addSong();
          },
        ),
        if (lines.value.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '右のつまみで並び替え・左にスワイプで削除',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
            ),
          ),
      ],
    );
  }

  /// 1 曲・全体の文字数上限に収まるよう切り詰める。
  static (List<String>, bool truncated) _fitToLimits(List<String> songs) {
    final result = <String>[];
    var totalLength = 0;
    var truncated = false;
    for (final raw in songs) {
      final song = raw.length > RecordFieldLimits.setlistSongLine
          ? raw.substring(0, RecordFieldLimits.setlistSongLine)
          : raw;
      // 改行区切りで保存するので、区切り文字分も数える
      final added = song.length + (result.isEmpty ? 0 : 1);
      if (totalLength + added > RecordFieldLimits.setlistTotal) {
        truncated = true;
        break;
      }
      totalLength += added;
      truncated |= song.length != raw.length;
      result.add(song);
    }
    return (result, truncated);
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFB71C1C),
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.only(right: 20),
          child: Icon(Icons.delete_outline_rounded, color: Colors.white),
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
          color: AppColors.gold.withValues(alpha: dimmed ? 0.35 : 0.8),
        ),
      ),
    );
  }
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
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.textDisabled.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: [
            _SongNumber(widget.number),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                scrollPadding: widget.scrollPadding,
                maxLength: RecordFieldLimits.setlistSongLine,
                minLines: 1,
                maxLines: 2,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                ),
                cursorColor: AppColors.gold,
                decoration: const InputDecoration(
                  counterText: '',
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: widget.onChanged,
              ),
            ),
            ReorderableDragStartListener(
              index: widget.index,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 20,
                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                ),
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
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int nextNumber;
  final bool hasSongs;
  final EdgeInsets scrollPadding;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 6),
      child: Row(
        children: [
          _SongNumber(nextNumber, dimmed: true),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              maxLength: RecordFieldLimits.setlistSongLine,
              scrollPadding: scrollPadding,
              textInputAction: TextInputAction.done,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
              ),
              cursorColor: AppColors.gold,
              decoration: InputDecoration(
                hintText: hasSongs ? '次の曲を追加' : '1曲目の曲名を入力',
                hintStyle: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                ),
                counterText: '',
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              // 連続入力しやすいよう、確定してもキーボードを閉じない
              onEditingComplete: onSubmit,
            ),
          ),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, value, _) {
              final enabled = value.text.trim().isNotEmpty;
              return IconButton(
                onPressed: enabled ? onSubmit : null,
                tooltip: '追加',
                icon: Icon(
                  Icons.add_circle_rounded,
                  color: enabled ? AppColors.gold : AppColors.textDisabled,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
