import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/widgets/record_form/record_date_row.dart';
import 'package:recolle/features/records/widgets/record_form/record_time_row.dart';

Future<void> _pump(WidgetTester tester, Widget row) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: SingleChildScrollView(child: row)),
    ),
  );
}

void main() {
  testWidgets('日付のホイールは「完了」で閉じ、選んだ日付を残す', (tester) async {
    var date = DateTime(2024, 10, 31);
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => RecordDateRow(
          label: '公演日',
          date: date,
          onChanged: (d) => setState(() => date = d),
        ),
      ),
    );

    await tester.tap(find.text('公演日'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);

    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoDatePicker), findsNothing);
    expect(find.text('完了'), findsNothing);
    expect(date, DateTime(2024, 10, 31));
  });

  group('別の項目にフォーカスが移ると閉じる', () {
    Future<void> pumpForm(WidgetTester tester) {
      var date = DateTime(2024, 10, 31);
      ClockTime? time;
      return _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              const CupertinoTextField(placeholder: '会場'),
              RecordDateRow(
                label: '公演日',
                date: date,
                onChanged: (d) => setState(() => date = d),
              ),
              RecordTimeRow(
                label: '開演',
                time: time,
                onChanged: (t) => setState(() => time = t),
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('入力欄をタップすると日付のホイールを閉じる', (tester) async {
      await pumpForm(tester);
      await tester.tap(find.text('公演日'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);

      await tester.showKeyboard(find.byType(CupertinoTextField));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoDatePicker), findsNothing);
    });

    testWidgets('別のホイールを開くと、開いていたホイールを閉じる', (tester) async {
      await pumpForm(tester);
      await tester.tap(find.text('公演日'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('開演'));
      await tester.pumpAndSettle();

      final picker = tester.widget<CupertinoDatePicker>(
        find.byType(CupertinoDatePicker),
      );
      expect(picker.mode, CupertinoDatePickerMode.time);
    });

    testWidgets('日付を開くと、入力中の欄のキーボードを閉じる', (tester) async {
      await pumpForm(tester);
      await tester.showKeyboard(find.byType(CupertinoTextField));
      await tester.pumpAndSettle();

      await tester.tap(find.text('公演日'));
      await tester.pumpAndSettle();

      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
    });
  });

  testWidgets('時刻のホイールは「完了」で閉じ、開いたときの時刻を確定する', (tester) async {
    ClockTime? time;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => RecordTimeRow(
          label: '開演',
          time: time,
          onChanged: (t) => setState(() => time = t),
        ),
      ),
    );

    await tester.tap(find.text('開演'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);

    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoDatePicker), findsNothing);
    expect(time, const ClockTime(18, 0));
    expect(find.text('18:00'), findsOneWidget);
  });
}
