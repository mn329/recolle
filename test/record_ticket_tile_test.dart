import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/components/record_ticket_list.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/features/records/models/record.dart';

void main() {
  testWidgets('チケットを長押しするとプレビュー付きのメニューが開き、閉じられる', (tester) async {
    // 縦向きの iPhone。横向きとはメニューの並べ方が変わり、プレビューの幅の決まり方も違う
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [isOfflineReadOnlyProvider.overrideWithValue(false)],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ListView(
              children: [
                RecordTicketTile(
                  record: Record(
                    id: 'r1',
                    type: RecordType.live,
                    title: 'ARENA TOUR',
                    artistOrAuthor: 'King Gnu',
                    date: DateTime(2026, 9, 27),
                    ticketImageUrl: '',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.text('ARENA TOUR'));
    await tester.pumpAndSettle();
    expect(find.text('編集'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('編集'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
