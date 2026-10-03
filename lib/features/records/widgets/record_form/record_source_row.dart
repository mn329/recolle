import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/features/records/field_suggestions.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/widgets/record_form/form_row_parts.dart';
import 'package:recolle/features/records/widgets/record_form/form_text_row.dart';
import 'package:recolle/features/records/widgets/record_form/inline_picker_panel.dart';

/// チケット取得元の行。取得元はほぼ決まった顔ぶれなので、自由入力ではなく一覧から選ばせる。
///
/// 一覧は自分の記録でよく使う取得元と、種別ごとの定番。ここに無いものは「その他」で自由に書ける。
class RecordSourceRow extends HookConsumerWidget {
  const RecordSourceRow({
    super.key,
    required this.type,
    required this.controller,
    required this.onChanged,
    required this.scrollPadding,
  });

  final RecordType type;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final EdgeInsets scrollPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records =
        ref.watch(recordsProvider).asData?.value ?? const <Record>[];
    // 取り込みなどで外から値が変わっても、表示と選択肢を追従させる
    final current = useValueListenable(controller).text;
    return _RecordSourceRow(
      type: type,
      controller: controller,
      onChanged: onChanged,
      scrollPadding: scrollPadding,
      options: sourceOptions(records: records, type: type, current: current),
    );
  }
}

class _RecordSourceRow extends StatefulWidget {
  const _RecordSourceRow({
    required this.type,
    required this.controller,
    required this.onChanged,
    required this.scrollPadding,
    required this.options,
  });

  final RecordType type;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final EdgeInsets scrollPadding;
  final List<String> options;

  @override
  State<_RecordSourceRow> createState() => _RecordSourceRowState();
}

class _RecordSourceRowState extends State<_RecordSourceRow>
    with InlinePickerExpansion {
  /// ホイールの先頭（取得元を空にする）。
  static const _unsetLabel = '未設定';

  /// ホイールの末尾。選んで「完了」を押すと自由入力に切り替わる。
  static const _freeLabel = 'その他（自由入力）';

  /// 自由入力に切り替えている間。一覧から選び直すまで入力欄を出す。
  bool _free = false;
  final _freeFocusNode = FocusNode(debugLabel: 'RecordSourceFree');

  /// ホイールで今どこを指しているか。値の反映は回したそばから、
  /// 自由入力への切り替えだけは「完了」を押してから行う。
  int _index = 0;
  FixedExtentScrollController? _wheelController;

  List<String> get _items => [_unsetLabel, ...widget.options, _freeLabel];

  @override
  void dispose() {
    _wheelController?.dispose();
    _freeFocusNode.dispose();
    super.dispose();
  }

  void _open() {
    final current = widget.controller.text.trim();
    final found = widget.options.indexOf(current);
    _index = current.isEmpty || found < 0 ? 0 : found + 1;
    _wheelController?.dispose();
    _wheelController = FixedExtentScrollController(initialItem: _index);
    setState(() => _free = false);
    setExpanded(true);
  }

  void _handleWheel(int index) {
    setState(() => _index = index);
    if (index == _items.length - 1) {
      if (widget.controller.text.isNotEmpty) {
        widget.controller.clear();
        widget.onChanged('');
      }
      return;
    }
    final value = index == 0 ? '' : widget.options[index - 1];
    if (widget.controller.text == value) return;
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged(value);
  }

  void _done() {
    final toFree = _index == _items.length - 1;
    setExpanded(false);
    if (!toFree) return;
    setState(() => _free = true);
    // 入力欄が組み上がってからフォーカスを移す
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _freeFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_free) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormTextRow(
            controller: widget.controller,
            focusNode: _freeFocusNode,
            placeholder: widget.type.sourcePlaceholder,
            icon: _icon,
            enLabel: widget.type.sourceEnLabel,
            maxLength: RecordFieldLimits.ticketSource,
            scrollPadding: widget.scrollPadding,
            onChanged: widget.onChanged,
          ),
          // 自由入力に切り替えたあとも一覧に戻れるようにする
          Align(
            alignment: Alignment.centerRight,
            child: CupertinoButton(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              minimumSize: const Size(44, 32),
              onPressed: _open,
              child: Text(
                '一覧から選ぶ',
                style: TextStyle(fontSize: 14, color: context.colors.accent),
              ),
            ),
          ),
        ],
      );
    }
    return Focus(
      focusNode: pickerFocusNode,
      child: FormRowHighlight(active: expanded, child: _buildRow(context)),
    );
  }

  IconData get _icon => widget.type == RecordType.book
      ? CupertinoIcons.bag
      : CupertinoIcons.tickets;

  Widget _buildRow(BuildContext context) {
    final value = widget.controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoButton(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          minimumSize: const Size(0, 48),
          pressedOpacity: 0.6,
          onPressed: expanded ? () => setExpanded(false) : _open,
          child: Row(
            children: [
              Expanded(
                child: FormRowTitle(
                  label: widget.type.sourceLabel,
                  icon: _icon,
                  enLabel: widget.type.sourceEnLabel,
                  active: expanded,
                ),
              ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.fill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    value.isEmpty ? _unsetLabel : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: value.isEmpty
                          ? context.colors.textSecondary
                          : expanded
                          ? context.colors.accent
                          : context.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? InlinePickerPanel(
                  onDone: _done,
                  picker: CupertinoPicker(
                    scrollController: _wheelController,
                    itemExtent: 36,
                    onSelectedItemChanged: _handleWheel,
                    children: [
                      for (final item in _items)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              item,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
