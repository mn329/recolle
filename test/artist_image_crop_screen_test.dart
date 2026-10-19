import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/theme/app_theme.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/screens/artist_image_crop_screen.dart';

/// 色つきの [width]x[height] の PNG を [dir] に書き出す。
Future<File> _writePng(Directory dir, int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366CC),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return File(
    '${dir.path}/source.png',
  ).writeAsBytes(data!.buffer.asUint8List());
}

void main() {
  late Directory dir;
  late File source;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('artist_crop_screen');
    // ファイルの読み込みと画像の処理は実際の非同期処理なので、テストの偽の時計の外で行う
    source = (await TestWidgetsFlutterBinding.ensureInitialized().runAsync(
      () => _writePng(dir, 400, 200),
    ))!;
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// [condition] が満たされるまで、実際の時間を進めながら描画する。
  Future<void> waitUntil(
    WidgetTester tester,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('待っていた状態になりませんでした');
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  /// 「完了」が押せる状態か（まだ画面に出ていなければ false）。
  bool doneEnabled(WidgetTester tester) {
    final finder = find.widgetWithText(NavBarTextButton, '完了');
    return finder.evaluate().isNotEmpty &&
        tester.widget<NavBarTextButton>(finder).onPressed != null;
  }

  /// 切り抜き画面を開いて、閉じたときに返された値を [onResult] に渡す。
  Future<void> openCropScreen(
    WidgetTester tester, {
    required File file,
    required ArtistImageFinisher finisher,
    required void Function(File? result) onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<File>(
                  MaterialPageRoute(
                    builder: (_) =>
                        ArtistImageCropScreen(file: file, finisher: finisher),
                  ),
                );
                onResult(result);
              },
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('画像を読み込むと切り抜きの画面が出て、キャンセルすると何も返さずに閉じる', (tester) async {
    var closed = false;
    File? result = File('unset');
    await openCropScreen(
      tester,
      file: source,
      finisher: (_) async => fail('キャンセルでは呼ばれない'),
      onResult: (value) {
        closed = true;
        result = value;
      },
    );

    await waitUntil(tester, () => find.byType(Crop).evaluate().isNotEmpty);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('枠は動かさず画像を動かす画面なので、四隅の丸い操作点は出さない', (tester) async {
    await openCropScreen(
      tester,
      file: source,
      finisher: (_) async => fail('呼ばれない'),
      onResult: (_) {},
    );
    await waitUntil(tester, () => find.byType(Crop).evaluate().isNotEmpty);
    await waitUntil(tester, () => doneEnabled(tester));

    expect(find.byType(DotControl), findsNothing);
  });

  testWidgets('完了を押すと、切り抜いた画像を仕上げて、そのファイルを返して閉じる', (tester) async {
    final output = File('${dir.path}/finished.jpg');
    Uint8List? received;
    File? result;
    await openCropScreen(
      tester,
      file: source,
      finisher: (cropped) async {
        received = cropped;
        return output;
      },
      onResult: (value) => result = value,
    );
    await waitUntil(tester, () => find.byType(Crop).evaluate().isNotEmpty);
    // 画像の準備が終わるまで、完了は押せない
    await waitUntil(tester, () => doneEnabled(tester));

    await tester.tap(find.text('完了'));
    await waitUntil(tester, () => result != null);
    await tester.pumpAndSettle();

    expect(result, output);
    expect(received, isNotNull);
    // 受け取ったのは切り抜いた画像で、正方形になっている
    final codec = await tester.runAsync(
      () => ui.instantiateImageCodec(received!),
    );
    final frame = await tester.runAsync(() => codec!.getNextFrame());
    expect(frame!.image.width, frame.image.height);
  });

  testWidgets('仕上げに失敗したら、閉じずにエラーを出して、もう一度試せる', (tester) async {
    var closed = false;
    var attempts = 0;
    await openCropScreen(
      tester,
      file: source,
      finisher: (_) async {
        attempts++;
        throw Exception('compress failed');
      },
      onResult: (_) => closed = true,
    );
    await waitUntil(tester, () => doneEnabled(tester));

    await tester.tap(find.text('完了'));
    await waitUntil(tester, () => attempts == 1);
    await tester.pumpAndSettle();

    expect(closed, isFalse);
    expect(find.byType(Crop), findsOneWidget);
    expect(doneEnabled(tester), isTrue);
  });

  testWidgets('画像を読み込めなかったら、メッセージを出して、キャンセルで閉じられる', (tester) async {
    var closed = false;
    await openCropScreen(
      tester,
      file: File('${dir.path}/missing.png'),
      finisher: (_) async => fail('呼ばれない'),
      onResult: (_) => closed = true,
    );
    await waitUntil(
      tester,
      () => find.text('画像を読み込めませんでした').evaluate().isNotEmpty,
    );

    expect(find.byType(Crop), findsNothing);
    expect(doneEnabled(tester), isFalse);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });
}
