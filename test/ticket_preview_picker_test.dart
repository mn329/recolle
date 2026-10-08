import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/record_form_state.dart';
import 'package:recolle/features/records/widgets/record_form/ticket_preview_picker.dart';

void main() {
  final images = [
    PickedTicketImage(File('a.jpg')),
    PickedTicketImage(File('b.jpg')),
  ];

  Future<({List<int> covers, List<int> removed})> pump(
    WidgetTester tester,
  ) async {
    final covers = <int>[];
    final removed = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ListView(
            children: [
              TicketPreviewPicker(
                type: RecordType.live,
                title: 'ツアー',
                artistOrAuthor: 'Aimer',
                date: DateTime(2026),
                images: images,
                onAddImages: () {},
                onRemoveImage: removed.add,
                onMakeCover: covers.add,
              ),
            ],
          ),
        ),
      ),
    );
    return (covers: covers, removed: removed);
  }

  testWidgets('画像をタップするだけで表紙になる', (tester) async {
    final calls = await pump(tester);

    await tester.tap(find.bySemanticsLabel('チケット画像'));
    await tester.pump();

    expect(calls.covers, [1]);
    expect(calls.removed, isEmpty);
    expect(find.byType(CupertinoActionSheet), findsNothing);
  });

  testWidgets('表紙の画像はタップしても何も起きない', (tester) async {
    final calls = await pump(tester);

    await tester.tap(find.bySemanticsLabel(RegExp('^表紙の画像')));
    await tester.pump();

    expect(calls.covers, isEmpty);
    expect(calls.removed, isEmpty);
  });

  testWidgets('× ボタンで画像を外す', (tester) async {
    final calls = await pump(tester);

    await tester.tap(find.bySemanticsLabel('画像を外す').last);
    await tester.pump();

    expect(calls.removed, [1]);
    expect(calls.covers, isEmpty);
  });
}
