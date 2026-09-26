import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:recolle/core/theme/app_colors.dart';

/// 年月日をホイールで選ぶピッカー（ボトムシート内で利用）。
class NumberDatePickerSheet extends StatefulWidget {
  const NumberDatePickerSheet({
    super.key,
    required this.initialDate,
    required this.onDateChanged,
  });

  final DateTime initialDate;
  final ValueChanged<DateTime> onDateChanged;

  @override
  State<NumberDatePickerSheet> createState() => _NumberDatePickerSheetState();
}

class _NumberDatePickerSheetState extends State<NumberDatePickerSheet> {
  late FixedExtentScrollController _yearController;
  late FixedExtentScrollController _monthController;
  late FixedExtentScrollController _dayController;

  late int _selectedYear;
  late int _selectedMonth;
  late int _selectedDay;

  final int _minYear = 2000;
  final int _maxYear = 2100;

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialDate.year;
    _selectedMonth = widget.initialDate.month;
    _selectedDay = widget.initialDate.day;

    _yearController = FixedExtentScrollController(
      initialItem: _selectedYear - _minYear,
    );
    _monthController = FixedExtentScrollController(
      initialItem: _selectedMonth - 1,
    );
    _dayController = FixedExtentScrollController(initialItem: _selectedDay - 1);
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    super.dispose();
  }

  void _updateDate() {
    final daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    if (_selectedDay > daysInMonth) {
      _selectedDay = daysInMonth;
      if (_dayController.hasClients) {
        _dayController.jumpToItem(_selectedDay - 1);
      }
    }

    widget.onDateChanged(DateTime(_selectedYear, _selectedMonth, _selectedDay));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Row(
        children: [
          Expanded(
            child: CupertinoPicker.builder(
              scrollController: _yearController,
              itemExtent: 40,
              onSelectedItemChanged: (index) {
                _selectedYear = _minYear + index;
                _updateDate();
              },
              itemBuilder: (context, index) {
                if (index < 0 || index > (_maxYear - _minYear)) return null;
                return Center(
                  child: Text(
                    '${_minYear + index}',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                );
              },
              childCount: _maxYear - _minYear + 1,
            ),
          ),
          Expanded(
            child: CupertinoPicker.builder(
              scrollController: _monthController,
              itemExtent: 40,
              onSelectedItemChanged: (index) {
                _selectedMonth = index + 1;
                _updateDate();
              },
              itemBuilder: (context, index) {
                return Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                );
              },
              childCount: 12,
            ),
          ),
          Expanded(
            child: CupertinoPicker.builder(
              scrollController: _dayController,
              itemExtent: 40,
              onSelectedItemChanged: (index) {
                _selectedDay = index + 1;
                widget.onDateChanged(
                  DateTime(_selectedYear, _selectedMonth, _selectedDay),
                );
              },
              itemBuilder: (context, index) {
                return Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                );
              },
              childCount: DateTime(_selectedYear, _selectedMonth + 1, 0).day,
            ),
          ),
        ],
      ),
    );
  }
}
