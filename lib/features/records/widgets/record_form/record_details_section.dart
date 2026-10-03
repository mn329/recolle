import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/record_form_state.dart';
import 'package:recolle/features/records/widgets/record_form/form_section.dart';
import 'package:recolle/features/records/widgets/record_form/form_text_row.dart';
import 'package:recolle/features/records/widgets/record_form/record_source_row.dart';
import 'package:recolle/features/records/widgets/record_form/record_time_row.dart';
import 'package:recolle/features/records/widgets/record_form/record_venue_row.dart';

/// 開場・開演・終演、会場・座席・料金・取得元をまとめた入力セクション。
/// 種別で使わない項目は出さない。
class RecordDetailsSection extends StatelessWidget {
  const RecordDetailsSection({
    super.key,
    required this.form,
    required this.controllers,
    required this.onTextChanged,
    required this.onOpenTimeChanged,
    required this.onStartTimeChanged,
    required this.onEndTimeChanged,
    required this.scrollPadding,
  });

  final RecordFormState form;
  final Map<RecordTextField, TextEditingController> controllers;
  final void Function(RecordTextField field, String value) onTextChanged;
  final ValueChanged<ClockTime?> onOpenTimeChanged;
  final ValueChanged<ClockTime?> onStartTimeChanged;
  final ValueChanged<ClockTime?> onEndTimeChanged;
  final EdgeInsets scrollPadding;

  FormTextRow _textRow(
    RecordTextField field, {
    required String placeholder,
    required IconData icon,
    required String enLabel,
    int? maxLength,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? suffix,
    FocusNode? focusNode,
  }) => FormTextRow(
    controller: controllers[field]!,
    focusNode: focusNode,
    placeholder: placeholder,
    icon: icon,
    enLabel: enLabel,
    maxLength: maxLength,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    suffix: suffix,
    scrollPadding: scrollPadding,
    onChanged: (value) => onTextChanged(field, value),
  );

  @override
  Widget build(BuildContext context) {
    final kind = form.type;
    // 未設定の時刻行を開いたときは、ほかの時刻から見当を付ける
    // （開演の 1 時間前を開場、2 時間後を終演とする）
    return FormSection(
      header: kind.detailsSectionLabel,
      children: [
        if (kind.hasOpenTime)
          RecordTimeRow(
            label: '開場',
            icon: CupertinoIcons.clock,
            enLabel: 'OPEN',
            time: form.openTime,
            defaultTime:
                form.startTime?.shiftedBy(-60) ?? const ClockTime(17, 0),
            onChanged: onOpenTimeChanged,
          ),
        if (kind.hasSchedule) ...[
          RecordTimeRow(
            label: kind.startTimeLabel,
            icon: CupertinoIcons.play_circle,
            enLabel: 'START',
            time: form.startTime,
            defaultTime: form.openTime?.shiftedBy(60) ?? const ClockTime(18, 0),
            onChanged: onStartTimeChanged,
          ),
          RecordTimeRow(
            label: kind.endTimeLabel,
            icon: CupertinoIcons.stop_circle,
            enLabel: 'END',
            time: form.endTime,
            defaultTime:
                form.startTime?.shiftedBy(120) ?? const ClockTime(20, 0),
            onChanged: onEndTimeChanged,
          ),
        ],
        if (form.hasVenue)
          RecordVenueRow(
            type: kind,
            controller: controllers[RecordTextField.venue]!,
            onChanged: (value) => onTextChanged(RecordTextField.venue, value),
            scrollPadding: scrollPadding,
          ),
        if (form.hasSeat)
          _textRow(
            RecordTextField.seat,
            placeholder: kind.seatPlaceholder!,
            icon: CupertinoIcons.square_grid_2x2,
            enLabel: 'SEAT',
            maxLength: RecordFieldLimits.seat,
          ),
        _textRow(
          RecordTextField.price,
          placeholder: kind.priceLabel,
          icon: CupertinoIcons.money_yen,
          enLabel: 'PRICE',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(
              '${RecordFieldLimits.ticketPriceMax}'.length,
            ),
          ],
          suffix: '円',
        ),
        RecordSourceRow(
          type: kind,
          controller: controllers[RecordTextField.source]!,
          onChanged: (value) => onTextChanged(RecordTextField.source, value),
          scrollPadding: scrollPadding,
        ),
        _textRow(
          RecordTextField.link,
          placeholder: 'リンク（公演ページ・チケットのページなど）',
          icon: CupertinoIcons.link,
          enLabel: 'LINK',
          maxLength: RecordFieldLimits.linkUrl,
          keyboardType: TextInputType.url,
        ),
      ],
    );
  }
}
