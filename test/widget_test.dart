import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/screens/home_screen.dart';

void main() {
  testWidgets('HomeScreen renders title and add button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // テストではSupabaseに依存しないよう、recordsを空で固定
          recordsProvider.overrideWith((ref) => Stream.value(<Record>[])),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('RECOLLE'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
