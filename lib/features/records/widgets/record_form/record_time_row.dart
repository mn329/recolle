import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/widgets/record_form/inline_picker_panel.dart';

/// 開演時刻などの任意の時刻の行。未設定なら「未設定」と出し、タップで行の下にホイールを開く。
class RecordTimeRow extends StatefulWidget {
  const RecordTimeRow({
    super.key,
    required this.label,
    required this.time,
    required this.onChanged,
    this.defaultTime = const ClockTime(18, 0),
  });

  final String label;
  final ClockTime? time;
  final ValueChanged<ClockTime?> onChanged;

  /// 未設定の状態から開いたときに入れる時刻。ライブの開演はほぼ夕方なので 18:00。
  final ClockTime defaultTime;

  @override
  State<RecordTimeRow> createState() => _RecordTimeRowState();
}

class _RecordTimeRowState extends State<RecordTimeRow> {
  bool _expanded = false;

  void _toggle() {
    FocusScope.of(context).unfocus();
    if (!_expanded && widget.time == null) widget.onChanged(widget.defaultTime);
    setState(() => _expanded = !_expanded);
  }

  void _clear() {
    widget.onChanged(null);
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final time = widget.time;
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
              if (time != null)
                CupertinoButton(
                  padding: const EdgeInsets.only(right: 8),
                  minimumSize: const Size(32, 32),
                  onPressed: _clear,
                  child: Icon(
                    CupertinoIcons.clear_circled_solid,
                    size: 18,
                    color: context.colors.textDisabled,
                    semanticLabel: '${widget.label}を消す',
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: context.colors.fill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  time?.format() ?? '未設定',
                  style: time == null
                      ? TextStyle(
                          fontSize: 15,
                          color: context.colors.textSecondary,
                        )
                      : AppFonts.monoStyle(
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
          child: _expanded && time != null
              ? InlinePickerPanel(
                  onDone: () => setState(() => _expanded = false),
                  picker: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: true,
                    minuteInterval: 5,
                    initialDateTime: DateTime(
                      2000,
                      1,
                      1,
                      time.hour,
                      time.minute - time.minute % 5,
                    ),
                    onDateTimeChanged: (d) =>
                        widget.onChanged(ClockTime(d.hour, d.minute)),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
