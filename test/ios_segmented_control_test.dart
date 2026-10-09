import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';

void main() {
  Future<ValueNotifier<String>> pump(WidgetTester tester) async {
    final selected = ValueNotifier('a');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ValueListenableBuilder<String>(
            valueListenable: selected,
            builder: (_, value, _) => IosSegmentedControl<String>(
              value: value,
              segments: const {'a': 'ライブ', 'b': '映画', 'c': '本'},
              onChanged: (v) => selected.value = v,
            ),
          ),
        ),
      ),
    );
    return selected;
  }

  testWidgets('タップで選択が切り替わり、選択中のセグメントのタップは何もしない', (tester) async {
    final selected = await pump(tester);

    await tester.tap(find.text('映画'));
    await tester.pumpAndSettle();
    expect(selected.value, 'b');

    await tester.tap(find.text('映画'));
    await tester.pumpAndSettle();
    expect(selected.value, 'b');

    await tester.tap(find.text('本'));
    await tester.pumpAndSettle();
    expect(selected.value, 'c');
  });

  testWidgets('選択中のセグメントを押している途中で別の画面が重なっても、あとのタップを受け付ける', (tester) async {
    final selected = await pump(tester);

    final touch = await tester.startGesture(tester.getCenter(find.text('ライブ')));
    await tester.pump(const Duration(milliseconds: 100));
    final navigator = Navigator.of(tester.element(find.byType(Scaffold)));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('X'))),
    );
    await tester.pumpAndSettle();
    await touch.up();
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('映画'));
    await tester.pumpAndSettle();
    expect(selected.value, 'b');
  });
}
