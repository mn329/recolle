import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/japanese_date_format.dart';
import 'package:recolle/features/records/widgets/record_form/inline_picker_panel.dart';

/// 日付の行。タップするとカレンダーアプリと同じく、行の下にホイールが開く。
class RecordDateRow extends StatefulWidget {
  const RecordDateRow({
    super.key,
    required this.label,
    required this.date,
    required this.onChanged,
  });

  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  State<RecordDateRow> createState() => _RecordDateRowState();
}

class _RecordDateRowState extends State<RecordDateRow> {
  static const _minimumYear = 2000;
  static const _maximumYear = 2100;

  bool _expanded = false;

  void _toggle() {
    FocusScope.of(context).unfocus();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoButton(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          minimumSize: const Size(0, 48),
          pressedOpacity: 0.6,
          onPressed: _toggle,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 16,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: context.colors.fill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  formatJapaneseDate(
                    widget.date,
                    includeWeekday: true,
                    padMonthDay: true,
                  ),
                  style: AppFonts.monoStyle(
                    fontSize: 15,
                    color: _expanded
                        ? context.colors.accent
                        : context.colors.textPrimary,
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
          child: _expanded
              ? InlinePickerPanel(
                  onDone: () => setState(() => _expanded = false),
                  picker: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    dateOrder: DatePickerDateOrder.ymd,
                    initialDateTime: widget.date,
                    minimumYear: _minimumYear,
                    maximumYear: _maximumYear,
                    onDateTimeChanged: (d) =>
                        widget.onChanged(DateTime(d.year, d.month, d.day)),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
