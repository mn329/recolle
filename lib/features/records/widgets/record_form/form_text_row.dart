import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/features/records/widgets/record_form/form_row_parts.dart';

/// [FormCard] の中に置く、枠のない iOS の入力行。
///
/// [icon] と [enLabel] を渡すと、左にアイコン、上にチケット風の項目名を添える。
/// 項目名の和文（[label]）は、プレースホルダーが消える入力後にだけ出す。
class FormTextRow extends StatefulWidget {
  const FormTextRow({
    super.key,
    required this.controller,
    required this.placeholder,
    this.icon,
    this.enLabel,
    this.label,
    this.focusNode,
    this.onChanged,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.textInputAction,
    this.keyboardType,
    this.inputFormatters,
    this.suffix,
    this.scrollPadding = const EdgeInsets.all(20),
  });

  final TextEditingController controller;
  final String placeholder;
  final IconData? icon;

  /// 「VENUE」のような英字の項目名。
  final String? enLabel;

  /// 「会場」のような和文の項目名。省略時は [placeholder] を使う。
  final String? label;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  /// 入力欄の右端に添える単位など（「円」）。
  final String? suffix;

  /// キーボード表示時に ensureVisible が十分スクロールするよう拡げる。
  final EdgeInsets scrollPadding;

  @override
  State<FormTextRow> createState() => _FormTextRowState();
}

class _FormTextRowState extends State<FormTextRow> {
  /// 常に「0/100」が並ぶと騒がしいので、上限が近づいてから出す。
  static const double _counterVisibleRatio = 0.8;

  static const double _horizontalPadding = 16;
  static const double _iconGap = 12;

  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode());

  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(FormTextRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocusNode)?.removeListener(
        _handleFocusChange,
      );
      _focusNode.addListener(_handleFocusChange);
      _handleFocusChange();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _ownFocusNode?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final multiline = widget.maxLines > 1;
    final limit = widget.maxLength;
    final icon = widget.icon;
    final enLabel = widget.enLabel;
    final contentStart = icon == null
        ? _horizontalPadding
        : _horizontalPadding + FormRowIcon.width + _iconGap;

    final field = CupertinoTextField(
      controller: widget.controller,
      focusNode: _focusNode,
      onChanged: widget.onChanged,
      placeholder: widget.placeholder,
      maxLines: widget.maxLines,
      minLines: widget.minLines ?? (multiline ? 3 : null),
      maxLength: widget.maxLength,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      suffix: widget.suffix == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: _horizontalPadding),
              child: Text(
                widget.suffix!,
                style: TextStyle(
                  fontSize: 16,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
      textInputAction:
          widget.textInputAction ??
          (multiline ? TextInputAction.newline : TextInputAction.next),
      scrollPadding: widget.scrollPadding,
      clearButtonMode: multiline
          ? OverlayVisibilityMode.never
          : OverlayVisibilityMode.editing,
      decoration: null,
      padding: EdgeInsets.fromLTRB(
        contentStart,
        enLabel == null ? 13 : 2,
        _horizontalPadding,
        13,
      ),
      cursorColor: context.colors.accent,
      style: TextStyle(
        fontSize: 16,
        height: 1.4,
        color: context.colors.textPrimary,
      ),
      placeholderStyle: TextStyle(
        fontSize: 16,
        height: 1.4,
        color: context.colors.textDisabled,
      ),
    );

    return FormRowHighlight(
      active: _focused,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (enLabel != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _focusNode.requestFocus,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      contentStart,
                      10,
                      _horizontalPadding,
                      0,
                    ),
                    child: ValueListenableBuilder(
                      valueListenable: widget.controller,
                      builder: (context, value, _) => FormFieldLabel(
                        en: enLabel,
                        ja: value.text.isEmpty
                            ? null
                            : widget.label ?? widget.placeholder,
                      ),
                    ),
                  ),
                ),
              field,
              if (limit != null)
                ValueListenableBuilder(
                  valueListenable: widget.controller,
                  builder: (context, value, _) {
                    final length = value.text.characters.length;
                    if (length < limit * _counterVisibleRatio) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _horizontalPadding,
                        0,
                        _horizontalPadding,
                        8,
                      ),
                      child: Text(
                        '$length / $limit',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          color: length >= limit
                              ? context.colors.destructive
                              : context.colors.textSecondary,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          if (icon != null)
            Positioned(
              left: _horizontalPadding,
              top: enLabel == null ? 15 : 22,
              child: IgnorePointer(child: FormRowIcon(icon, active: _focused)),
            ),
        ],
      ),
    );
  }
}
