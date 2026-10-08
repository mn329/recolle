import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/features/records/widgets/ticket_image_carousel.dart';

void main() {
  group('heightFor', () {
    const width = 360.0;
    const maxHeight = 480.0;

    test('横長の写真は切り抜かずに縦横比どおりの高さにする', () {
      expect(
        TicketImageCarousel.heightFor(
          aspectRatio: 16 / 9,
          width: width,
          maxHeight: maxHeight,
        ),
        closeTo(202.5, 0.01),
      );
    });

    test('縦画面で撮った写真は上限の高さで止める', () {
      expect(
        TicketImageCarousel.heightFor(
          aspectRatio: 9 / 16,
          width: width,
          maxHeight: maxHeight,
        ),
        maxHeight,
      );
    });

    test('極端に横長でも低くなりすぎない', () {
      expect(
        TicketImageCarousel.heightFor(
          aspectRatio: 5,
          width: width,
          maxHeight: maxHeight,
        ),
        TicketImageCarousel.minHeight,
      );
    });

    test('縦横比が分からないうちは仮の高さにする', () {
      expect(
        TicketImageCarousel.heightFor(
          aspectRatio: null,
          width: width,
          maxHeight: maxHeight,
        ),
        TicketImageCarousel.placeholderHeight,
      );
    });
  });

  testWidgets('画像がなければ何も出さず、複数枚なら何枚目かを示す', (tester) async {
    Future<void> pump(List<String> urls) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: TicketImageCarousel(urls: urls)),
      ),
    );

    await pump(const []);
    expect(find.byType(PageView), findsNothing);

    await pump(const [
      'https://example.com/a.jpg',
      'https://example.com/b.jpg',
    ]);
    await tester.pump();
    expect(find.byType(PageView), findsOneWidget);
    expect(find.bySemanticsLabel('2枚中1枚目'), findsOneWidget);
  });
}
